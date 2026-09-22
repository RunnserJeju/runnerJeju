"""운영자용 원본 로그 열람 — GET /admin/user-logs.

대시보드 숫자는 metrics가 맡고, 여기는 행을 그대로 보는 창구다(특정 회원의 흐름,
새 로그의 detail 확인). 필터는 log_name·user_id·session_id·기간이고 최신순
keyset 페이지네이션이라 로그가 쌓여도 뒤 페이지가 느려지지 않는다. 회원 닉네임은
users를 조인해 붙인다(탈퇴자는 null).
"""

import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import String, cast, select, tuple_
from sqlalchemy.orm import Session

from app import user_log
from app.admin.metrics.registry import METRICS
from app.admin.metrics.sources import Period
from app.db import get_db
from app.models import User, UserLog
from app.schemas import LogNameOut, UserLogListOut

router = APIRouter(tags=["user-logs"])

CURSOR_SEP = "_"


def encode_cursor(created_at: datetime, log_id: uuid.UUID) -> str:
    return f"{created_at.isoformat()}{CURSOR_SEP}{log_id}"


def decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        ts, log_id = cursor.rsplit(CURSOR_SEP, 1)
        return datetime.fromisoformat(ts), uuid.UUID(log_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="cursor 형식이 잘못됐어요.")


@router.get("/user-logs/names", response_model=list[LogNameOut])
def list_log_names():
    """앱이 보낼 수 있는 로그 이름 목록(표시명·묶음 포함). 로그 화면의 필터 드롭다운용.

    표시명과 묶음은 지표 등록부와 같은 값을 쓴다 — 로그 이름마다 지표가 자동 등록되므로
    항상 존재한다.
    """
    return [
        {"name": name, "label": METRICS[name].label, "group": METRICS[name].group}
        for name in sorted(user_log.LOG_NAMES)
    ]


@router.get("/user-logs", response_model=UserLogListOut)
def list_user_logs(
    log_name: str | None = Query(default=None),
    user_id: str | None = Query(default=None),
    session_id: str | None = Query(default=None),
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    limit: int = Query(default=50, ge=1, le=100),
    cursor: str | None = Query(default=None),
    db: Session = Depends(get_db),
):
    filters = list(Period(start, end).clauses(UserLog.created_at))
    if log_name:
        filters.append(UserLog.log_name == log_name)
    if user_id:
        filters.append(UserLog.user_id == user_id)
    if session_id:
        filters.append(UserLog.session_id == session_id)
    if cursor:
        ts, log_id = decode_cursor(cursor)
        filters.append(tuple_(UserLog.created_at, UserLog.id) < (ts, log_id))

    # limit+1로 읽어 다음 페이지 유무를 안다.
    rows = db.execute(
        select(UserLog, User.nickname)
        .outerjoin(User, cast(User.id, String) == UserLog.user_id)
        .where(*filters)
        .order_by(UserLog.created_at.desc(), UserLog.id.desc())
        .limit(limit + 1)
    ).all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    items = [
        {
            "id": log.id,
            "log_name": log.log_name,
            "user_id": log.user_id,
            "nickname": nickname,
            "session_id": log.session_id,
            "detail": log.detail,
            "platform": log.platform,
            "app_version": log.app_version,
            "created_at": log.created_at,
        }
        for log, nickname in rows
    ]
    next_cursor = encode_cursor(rows[-1][0].created_at, rows[-1][0].id) if has_more else None
    return {"items": items, "next_cursor": next_cursor}
