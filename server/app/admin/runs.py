"""운영자 전용 러닝 기록 조회 — 모든 회원의 러닝을 기간별로, 시간순으로 한 행씩. 조회 전용.

기간(from/to)은 한국 날짜(KST) 기준 양끝 포함이다. 운영자가 "오늘"이라고 하면 KST 하루이고,
서버 지표의 '하루'도 KST라 같은 기준이다. runs.user_id는 users.id의 FK가 아니라 토큰 sub 문자열이라
캐스트해서 outer join한다(탈퇴해 행이 없으면 닉네임·이메일은 None).
"""

from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import Integer, String, cast, exists, func, or_, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Course, Run, User, UserLog, Verification
from app.schemas import AdminRunListOut

router = APIRouter(tags=["runs"])

KST = timezone(timedelta(hours=9))


def _kst_start(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=KST)


def _completion(course_id, status: str | None) -> str:
    """completed 완주 / pending 검증 중 / incomplete 미완주 / none 코스 없이 뛴 러닝."""
    if course_id is None:
        return "none"
    if status == "matched":
        return "completed"
    if status in ("pending", "inProgress"):
        return "pending"
    return "incomplete"


# run_recover가 기록을 올리기 전에 남으므로 기록 생성 뒤 이만큼까지만 본다(전송 지연 여유).
_RECOVER_LOG_SLACK = timedelta(minutes=5)


def _app_killed():
    """러닝 중 앱이 죽어 다음 실행 때 일지로 복구된 기록인지.

    기록에 표시가 없어 같은 사용자·코스·시간(초)의 run_recover 로그로 짝짓는다.
    이어달리기 구간이 복구된 경우는 합친 시간과 달라 잡히지 않는다.
    """
    return exists().where(
        UserLog.log_name == "run_recover",
        UserLog.user_id == Run.user_id,
        UserLog.created_at >= Run.ended_at,
        UserLog.created_at <= Run.created_at + _RECOVER_LOG_SLACK,
        UserLog.detail["elapsed_sec"].astext.cast(Integer) == Run.duration_sec,
        func.coalesce(UserLog.detail["course_id"].astext, "")
        == func.coalesce(cast(Run.course_id, String), ""),
    )


@router.get("/runs", response_model=AdminRunListOut)
def list_runs(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    order: str = Query(default="desc", pattern="^(asc|desc)$"),
    q: str = Query(default="", max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """기간 안(시작 시각 기준)의 모든 러닝. 기본은 최신순."""
    since = _kst_start(date_from)
    until = _kst_start(date_to) + timedelta(days=1)  # to 당일 끝까지
    where = [Run.started_at >= since, Run.started_at < until]
    keyword = q.strip()
    if keyword:
        # LIKE 와일드카드는 이스케이프해 글자 그대로 찾는다.
        like = "%" + keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        where.append(or_(User.nickname.ilike(like, escape="\\"), User.email.ilike(like, escape="\\")))

    user_join = cast(User.id, String) == Run.user_id
    total = db.scalar(
        select(func.count()).select_from(Run).outerjoin(User, user_join).where(*where)
    )

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
            Verification.status.label("verification_status"),
            Verification.match_rate,
            _app_killed().label("app_killed"),
        )
        .outerjoin(User, user_join)
        .outerjoin(Course, Course.id == Run.course_id)
        # 완주 = 그 코스에 대해 통과(matched)한 검증이 있음. (run, course)는 유일해 행이 늘지 않는다.
        .outerjoin(
            Verification,
            (Verification.run_id == Run.id) & (Verification.course_id == Run.course_id),
        )
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
                "match_rate": r.match_rate,
                "completion": _completion(r.course_id, r.verification_status),
                "app_killed": r.app_killed,
            }
            for r in rows
        ],
    }
