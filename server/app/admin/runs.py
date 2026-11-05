"""운영자 전용 러닝 기록 조회 — 모든 회원의 러닝을 기간별로, 시간순으로 한 행씩. 조회 전용.

기간(from/to)은 한국 날짜(KST) 기준 양끝 포함이다. 운영자가 "오늘"이라고 하면 KST 하루이고,
서버 지표의 '하루'도 KST라 같은 기준이다. runs.user_id는 users.id의 FK가 아니라 토큰 sub 문자열이라
캐스트해서 outer join한다(탈퇴해 행이 없으면 닉네임·이메일은 None).
"""

from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import String, cast, func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Course, Run, User
from app.schemas import AdminRunListOut

router = APIRouter(tags=["runs"])

KST = timezone(timedelta(hours=9))


def _kst_start(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=KST)


@router.get("/runs", response_model=AdminRunListOut)
def list_runs(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    order: str = Query(default="desc", pattern="^(asc|desc)$"),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """기간 안(시작 시각 기준)의 모든 러닝. 기본은 최신순."""
    since = _kst_start(date_from)
    until = _kst_start(date_to) + timedelta(days=1)  # to 당일 끝까지
    where = (Run.started_at >= since, Run.started_at < until)

    total = db.scalar(select(func.count()).select_from(Run).where(*where))

    started = Run.started_at.asc() if order == "asc" else Run.started_at.desc()
    rows = db.execute(
        select(
            Run.id,
            Run.user_id,
            User.nickname,
            User.email,
            Run.course_id,
            Course.name,
            Run.distance_meters,
            Run.duration_sec,
            Run.started_at,
            Run.ended_at,
        )
        .outerjoin(User, cast(User.id, String) == Run.user_id)
        .outerjoin(Course, Course.id == Run.course_id)
        .where(*where)
        .order_by(started, Run.id)
        .limit(limit)
        .offset(offset)
    ).all()

    return {
        "total": total,
        "items": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "nickname": r.nickname,
                "email": r.email,
                "course_id": r.course_id,
                "course_name": r.name,
                "distance_km": round(r.distance_meters / 1000, 2),
                "duration_sec": r.duration_sec,
                "started_at": r.started_at,
                "ended_at": r.ended_at,
            }
            for r in rows
        ],
    }
