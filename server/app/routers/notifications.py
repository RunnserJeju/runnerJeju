import hmac
import os
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import case, delete, func, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app import notifications
from app.db import get_db
from app.deps import current_user_id
from app.models import DeviceToken, Notification
from app.schemas import DeviceRegister, DeviceUnregister, NotificationOut, UnreadCountOut

router = APIRouter(tags=["notifications"])

KST = timezone(timedelta(hours=9))
# 알림함에 보이는 날 수(오늘 포함, 한국 날짜). 행은 지우지 않는다(운영툴 기록).
INBOX_DAYS = 7


def _inbox_since() -> datetime:
    """알림함이 보여주는 가장 이른 시각 — 오늘을 포함한 최근 INBOX_DAYS일의 첫날 0시(KST)."""
    today = datetime.now(KST).replace(hour=0, minute=0, second=0, microsecond=0)
    return today - timedelta(days=INBOX_DAYS - 1)


@router.put("/devices", status_code=204)
def register_device(
    payload: DeviceRegister,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """기기 토큰과 OS 알림 권한을 등록·갱신한다. 같은 기기에서 계정이 바뀌면 토큰의 주인이 바뀐다."""
    values = dict(
        user_id=user_id,
        platform=payload.platform,
        permission=payload.permission,
        app_version=payload.app_version,
    )
    authorized = payload.permission == "authorized"
    statement = insert(DeviceToken).values(
        id=uuid.uuid4(),
        token=payload.token,
        authorized_at=func.now() if authorized else None,
        **values,
    )
    # 계속 허용이면 처음 허용한 시각을 지킨다. 껐다 다시 켜면 새로 찍는다.
    kept = case((DeviceToken.permission == "authorized", DeviceToken.authorized_at))
    db.execute(
        statement.on_conflict_do_update(
            index_elements=[DeviceToken.token],
            set_={
                **values,
                "authorized_at": func.coalesce(kept, func.now()) if authorized else None,
                "updated_at": func.now(),
            },
        )
    )
    db.commit()


@router.post("/devices/unregister", status_code=204)
def unregister_device(
    payload: DeviceUnregister,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """로그아웃 때. 토큰이 길고 주소에 남으면 안 돼 본문으로 받는다."""
    db.execute(
        delete(DeviceToken).where(
            DeviceToken.token == payload.token, DeviceToken.user_id == user_id
        )
    )
    db.commit()


@router.get("/notifications", response_model=list[NotificationOut])
def list_notifications(
    before: datetime | None = None,
    limit: int = Query(default=30, ge=1, le=50),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 알림함, 최신순. 다음 쪽은 마지막 항목의 created_at을 before로 넘긴다."""
    query = select(Notification).where(
        Notification.user_id == user_id,
        Notification.created_at >= _inbox_since(),
    )
    if before is not None:
        query = query.where(Notification.created_at < before)
    return db.execute(
        query.order_by(Notification.created_at.desc(), Notification.id.desc()).limit(limit)
    ).scalars().all()


@router.get("/notifications/unread-count", response_model=UnreadCountOut)
def unread_count(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    count = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
            Notification.created_at >= _inbox_since(),
        )
    )
    return UnreadCountOut(count=count or 0)


@router.post("/notifications/read-all", status_code=204)
def read_all(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    db.execute(
        update(Notification)
        .where(Notification.user_id == user_id, Notification.read_at.is_(None))
        .values(read_at=func.now())
    )
    db.commit()


@router.post("/notifications/{notification_id}/read", status_code=204)
def read_one(
    notification_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """알림함에서 열었거나 푸시를 눌러 들어왔을 때."""
    db.execute(
        update(Notification)
        .where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
        )
        .values(read_at=func.now())
    )
    db.commit()


@router.post("/internal/notifications/tick", include_in_schema=False)
def tick(
    x_tick_secret: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    """Cloud Scheduler(notification-tick)가 30분마다 부른다. NOTIFICATION_TICK_SECRET이 없으면 닫혀 있다."""
    secret = os.environ.get("NOTIFICATION_TICK_SECRET")
    if not secret or not x_tick_secret or not hmac.compare_digest(secret, x_tick_secret):
        raise HTTPException(status_code=404)
    return notifications.tick(db)
