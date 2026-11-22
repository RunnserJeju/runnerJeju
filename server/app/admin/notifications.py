"""운영자 전용 알림 — 수동 발송, 발송 내역·명단, 전체 알림 기록, 수신 현황.

발송은 행을 먼저 만들고(app/notifications.py) 묶음 단위로 보낸다. 만들 때 첫 묶음을 바로 보내고,
남은 건 화면이 dispatch를 되풀이해 부르거나 틱이 가져간다.
"""

import uuid
from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import String, cast, func, or_, select, text
from sqlalchemy.orm import Session

from app import notifications
from app.admin import audit
from app.admin.auth import require_admin_session
from app.db import get_db
from app.models import AdminUser, DeviceToken, Notification, NotificationSend, User
from app.notification_types import APP_LINK_PREFIX, OPERATOR_NOTICE, SCREENS, TYPES
from app.schemas import (
    AdminNotificationDeviceListOut,
    AdminNotificationDispatchOut,
    AdminNotificationListOut,
    AdminNotificationScreenOut,
    AdminNotificationSendCreate,
    AdminNotificationSendListOut,
    AdminNotificationSendOut,
    AdminNotificationTypeOut,
    NotificationAudience,
)

router = APIRouter(tags=["notifications"])

KST = timezone(timedelta(hours=9))
_UNSENT = ("pending", "sending")
_USER_JOIN = cast(User.id, String) == Notification.user_id


def _like(keyword: str) -> str:
    return "%" + keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _live_counts(db: Session, send_ids: list[uuid.UUID]) -> dict[uuid.UUID, dict[str, int]]:
    """아직 마감 안 된 발송의 상태별 수. done은 저장된 값을 쓴다."""
    counts: dict[uuid.UUID, dict[str, int]] = {}
    if not send_ids:
        return counts
    for send_id, status, count in db.execute(
        select(Notification.send_id, Notification.push_status, func.count())
        .where(Notification.send_id.in_(send_ids))
        .group_by(Notification.send_id, Notification.push_status)
    ):
        counts.setdefault(send_id, {})[status] = count
    return counts


def _send_out(
    send: NotificationSend, live: dict[str, int] | None = None, read_count: int | None = None
) -> AdminNotificationSendOut:
    out = AdminNotificationSendOut.model_validate(send)
    if live is not None:
        out.sent_count = live.get("sent", 0)
        out.failed_count = live.get("failed", 0)
        out.no_device_count = live.get("no_device", 0)
        out.no_permission_count = live.get("no_permission", 0)
        out.pending_count = sum(live.get(status, 0) for status in _UNSENT)
    out.read_count = read_count
    return out


def _load_send(db: Session, send_id: uuid.UUID) -> NotificationSend:
    send = db.get(NotificationSend, send_id)
    if send is None:
        raise HTTPException(status_code=404, detail="발송 건을 찾을 수 없어요.")
    return send


def _detail(db: Session, send: NotificationSend) -> AdminNotificationSendOut:
    live = _live_counts(db, [send.id]).get(send.id, {}) if send.status == "sending" else None
    read_count = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.send_id == send.id, Notification.read_at.is_not(None))
    )
    return _send_out(send, live, read_count or 0)


@router.get("/notification-types", response_model=list[AdminNotificationTypeOut])
def list_types(db: Session = Depends(get_db)):
    counts = dict(
        db.execute(select(Notification.type, func.count()).group_by(Notification.type)).all()
    )
    return [
        AdminNotificationTypeOut(
            key=t.key, label=t.label, automatic=t.automatic, count=counts.get(t.key, 0)
        )
        for t in TYPES.values()
    ]


@router.get("/notification-screens", response_model=list[AdminNotificationScreenOut])
def list_screens():
    """알림을 눌렀을 때 열 수 있는 앱 화면. 첫 항목(홈)이 기본값."""
    return [
        AdminNotificationScreenOut(link=APP_LINK_PREFIX + key, label=label)
        for key, label in SCREENS.items()
    ]


@router.post("/notification-sends/preview")
def preview_audience(payload: NotificationAudience, db: Session = Depends(get_db)):
    """발송 전 대상 인원."""
    return {"count": notifications.audience_count(db, payload.stored())}


@router.post("/notification-sends", response_model=AdminNotificationSendOut, status_code=201)
def create_send(
    payload: AdminNotificationSendCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin_session),
):
    """발송을 만든다. 즉시면 명단을 만들고 첫 묶음을 바로 보낸다."""
    if payload.scheduled_at is not None and payload.scheduled_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=422, detail="예약 시각은 지금 이후여야 해요.")
    send = notifications.create_send(
        db,
        admin,
        type=OPERATOR_NOTICE,
        title=payload.title,
        body=payload.body,
        link_url=payload.link_url,
        audience=payload.audience.stored(),
        scheduled_at=payload.scheduled_at,
    )
    if payload.scheduled_at is None and send.target_count == 0:
        db.rollback()
        raise HTTPException(status_code=422, detail="받을 회원이 없어요.")
    audit.record(
        db, admin, audit.NOTIFICATION_SEND,
        target_type="notification_send", target_id=send.id,
        detail={
            "title": send.title,
            "audience": send.audience["kind"],
            "target_count": send.target_count,
            "scheduled_at": payload.scheduled_at.isoformat() if payload.scheduled_at else None,
        },
    )
    db.commit()
    if send.status == "sending":
        notifications.dispatch(db, send_id=send.id)
        notifications.finish_sends(db)
    db.refresh(send)
    return _detail(db, send)


@router.post("/notification-sends/{send_id}/dispatch", response_model=AdminNotificationDispatchOut)
def dispatch_send(send_id: uuid.UUID, db: Session = Depends(get_db)):
    """남은 대기 건을 한 묶음 보낸다. 화면이 pending_count가 0이 되거나 processed가 0일 때까지 부른다."""
    send = _load_send(db, send_id)
    processed = 0
    if send.status == "sending":
        processed = notifications.dispatch(db, send_id=send.id)
        notifications.finish_sends(db)
        db.refresh(send)
    return AdminNotificationDispatchOut(processed=processed, send=_detail(db, send))


@router.post("/notification-sends/{send_id}/cancel", response_model=AdminNotificationSendOut)
def cancel_send(
    send_id: uuid.UUID,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin_session),
):
    """예약 건만 취소할 수 있다. 명단을 만든 뒤에는 이미 나가고 있다."""
    send = db.execute(
        select(NotificationSend).where(NotificationSend.id == send_id).with_for_update()
    ).scalar_one_or_none()
    if send is None:
        raise HTTPException(status_code=404, detail="발송 건을 찾을 수 없어요.")
    if send.status != "scheduled":
        raise HTTPException(status_code=409, detail="이미 발송이 시작돼 취소할 수 없어요.")
    send.status = "canceled"
    send.finished_at = datetime.now(timezone.utc)
    audit.record(
        db, admin, audit.NOTIFICATION_CANCEL,
        target_type="notification_send", target_id=send.id, detail={"title": send.title},
    )
    db.commit()
    db.refresh(send)
    return _send_out(send)


@router.get("/notification-sends", response_model=AdminNotificationSendListOut)
def list_sends(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """발송 건 목록, 최신순."""
    total = db.scalar(select(func.count()).select_from(NotificationSend))
    sends = db.execute(
        select(NotificationSend)
        .order_by(NotificationSend.created_at.desc())
        .limit(limit)
        .offset(offset)
    ).scalars().all()
    live = _live_counts(db, [s.id for s in sends if s.status == "sending"])
    return {
        "total": total,
        "items": [_send_out(s, live.get(s.id, {}) if s.status == "sending" else None) for s in sends],
    }


@router.get("/notification-sends/{send_id}", response_model=AdminNotificationSendOut)
def get_send(send_id: uuid.UUID, db: Session = Depends(get_db)):
    return _detail(db, _load_send(db, send_id))


def _notification_rows(db: Session, where: list, limit: int, offset: int) -> dict:
    total = db.scalar(
        select(func.count()).select_from(Notification).outerjoin(User, _USER_JOIN).where(*where)
    )
    rows = db.execute(
        select(Notification, User.nickname, User.email)
        .outerjoin(User, _USER_JOIN)
        .where(*where)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    return {
        "total": total,
        "items": [
            {
                "id": n.id,
                "send_id": n.send_id,
                "user_id": n.user_id,
                "nickname": nickname,
                "email": email,
                "type": n.type,
                "title": n.title,
                "body": n.body,
                "push_status": n.push_status,
                "push_error": n.push_error,
                "pushed_at": n.pushed_at,
                "read_at": n.read_at,
                "created_at": n.created_at,
            }
            for n, nickname, email in rows
        ],
    }


@router.get("/notification-sends/{send_id}/recipients", response_model=AdminNotificationListOut)
def list_recipients(
    send_id: uuid.UUID,
    status: str | None = Query(default=None, pattern="^(pending|sending|sent|failed|no_permission|no_device|skipped)$"),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """발송 명단 — 회원별 푸시 결과와 읽음."""
    _load_send(db, send_id)
    where = [Notification.send_id == send_id]
    if status:
        where.append(Notification.push_status == status)
    return _notification_rows(db, where, limit, offset)


@router.get("/notifications", response_model=AdminNotificationListOut)
def list_notifications(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    type: str | None = Query(default=None, max_length=40),
    q: str = Query(default="", max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """회원 단위 전체 알림 기록(수동·자동). 기간은 한국 날짜, 양끝 포함."""
    since = datetime.combine(date_from, time.min, tzinfo=KST)
    until = datetime.combine(date_to, time.min, tzinfo=KST) + timedelta(days=1)
    where = [Notification.created_at >= since, Notification.created_at < until]
    if type:
        where.append(Notification.type == type)
    keyword = q.strip()
    if keyword:
        like = _like(keyword)
        where.append(or_(User.nickname.ilike(like, escape="\\"), User.email.ilike(like, escape="\\")))
    return _notification_rows(db, where, limit, offset)


# 회원별로 기기를 접어 수신 상태 하나로. 한 대라도 허용이면 authorized.
_DEVICE_STATE_SQL = """
SELECT u.id AS user_id, u.nickname, u.email,
       CASE WHEN d.user_id IS NULL THEN 'none'
            WHEN d.any_authorized THEN 'authorized'
            WHEN d.any_denied THEN 'denied'
            ELSE 'not_determined' END AS permission,
       coalesce(d.platforms, ARRAY[]::varchar[]) AS platforms,
       d.app_version, coalesce(d.device_count, 0) AS device_count, d.authorized_at, d.updated_at
FROM users u
LEFT JOIN (
    SELECT user_id,
           bool_or(permission = 'authorized') AS any_authorized,
           bool_or(permission = 'denied') AS any_denied,
           array_agg(DISTINCT platform) AS platforms,
           (array_agg(app_version ORDER BY updated_at DESC))[1] AS app_version,
           count(*) AS device_count,
           min(authorized_at) FILTER (WHERE permission = 'authorized') AS authorized_at,
           max(updated_at) AS updated_at
    FROM device_tokens GROUP BY user_id
) d ON d.user_id = u.id::text
WHERE u.deleted_at IS NULL
"""


def permissions_by_user(db: Session, user_ids: list[str]) -> dict[str, str]:
    """회원 목록의 '알림' 열. 기기가 없는 회원은 결과에 없다(none)."""
    if not user_ids:
        return {}
    states: dict[str, str] = {}
    for user_id, permission in db.execute(
        select(DeviceToken.user_id, DeviceToken.permission).where(DeviceToken.user_id.in_(user_ids))
    ):
        current = states.get(user_id)
        if permission == "authorized" or current is None:
            states[user_id] = permission
        elif permission == "denied" and current != "authorized":
            states[user_id] = permission
    return states


@router.get("/notification-devices", response_model=AdminNotificationDeviceListOut)
def list_devices(
    permission: str | None = Query(default=None, pattern="^(authorized|denied|not_determined|none)$"),
    q: str = Query(default="", max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """수신 현황 — 알림 권한을 허용한 회원이 누구인지."""
    summary = {"authorized": 0, "denied": 0, "not_determined": 0, "none": 0}
    for state, count in db.execute(
        text(f"SELECT permission, count(*) FROM ({_DEVICE_STATE_SQL}) s GROUP BY permission")
    ):
        summary[state] = count

    filters, params = "", {"limit": limit, "offset": offset}
    if permission:
        filters += " AND s.permission = :permission"
        params["permission"] = permission
    keyword = q.strip()
    if keyword:
        filters += " AND (s.nickname ILIKE :like ESCAPE '\\' OR s.email ILIKE :like ESCAPE '\\')"
        params["like"] = _like(keyword)
    base = f"FROM ({_DEVICE_STATE_SQL}) s WHERE true{filters}"
    count_params = {k: v for k, v in params.items() if k not in ("limit", "offset")}
    total = db.execute(text(f"SELECT count(*) {base}"), count_params).scalar_one()
    rows = db.execute(
        text(
            f"SELECT s.* {base}"
            " ORDER BY s.updated_at DESC NULLS LAST, s.user_id LIMIT :limit OFFSET :offset"
        ),
        params,
    ).mappings().all()
    return {"total": total, "summary": summary, "items": [dict(row) for row in rows]}
