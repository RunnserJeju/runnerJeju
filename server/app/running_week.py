"""러닝위크 도메인. 러닝위크 기간에만 도는 보상(전용 스탬프·쿠폰·빙고)은 전부 여기 진입점
(on_course_completed)에서 시작한다.

- on_course_completed: 완주 인증 직후. 공개 중인 회차에 참가 신청한 사람에게만 그 회차 전용
  코스 스탬프·코스완료 쿠폰·빙고 보상을 준다.

쿠폰·스탬프 발급 규칙(app.coupon_rules, app.stamp_rules)과 빙고 계산(app.bingo)은 기간을
모른다. 기간 판단은 이 모듈만 한다. 커밋은 부르는 쪽이 한다.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import bingo, coupon_rules, stamp_rules
from app.models import RunningWeek, RunningWeekParticipation


def is_visible(week: RunningWeek, now: datetime, *, is_admin: bool) -> bool:
    """공지와 같은 규칙에 공개 범위가 더해진다. 꺼져 있거나 공개 기간 밖이면 앱에 안 뜨고,
    visibility='admin'인 회차는 운영자 계정에만 뜬다."""
    if not week.is_active:
        return False
    if week.visibility != "public" and not is_admin:
        return False
    if week.starts_at is not None and week.starts_at > now:
        return False
    if week.ends_at is not None and week.ends_at < now:
        return False
    return True


def current_week(db: Session, *, is_admin: bool) -> RunningWeek | None:
    """지금 공개 중인 러닝위크. 여럿이면 가장 늦게 시작한 회차. 일반 사용자에게는
    public 회차만."""
    now = datetime.now(timezone.utc)
    weeks = db.execute(
        select(RunningWeek).order_by(
            RunningWeek.starts_at.desc().nulls_last(), RunningWeek.created_at.desc()
        )
    ).scalars()
    return next((week for week in weeks if is_visible(week, now, is_admin=is_admin)), None)


def participated(db: Session, week_id: uuid.UUID, user_id: str) -> bool:
    return (
        db.execute(
            select(RunningWeekParticipation.id).where(
                RunningWeekParticipation.running_week_id == week_id,
                RunningWeekParticipation.user_id == user_id,
            )
        ).first()
        is not None
    )


def next_round(db: Session) -> int:
    """새 회차 번호. 지금까지 가장 큰 회차 + 1."""
    return (db.execute(select(func.max(RunningWeek.round))).scalar() or 0) + 1


def on_course_completed(
    db: Session, user_id: str, course_id: uuid.UUID, run_id: uuid.UUID
) -> None:
    """완주 인증이 통과했을 때. 러닝위크가 아니거나 참가자가 아니면 아무것도 하지 않는다."""
    # 운영자 전용 회차도 포함한다 — 참가 신청 여부가 이미 볼 수 있던 사람만 걸러 준다.
    week = current_week(db, is_admin=True)
    if week is None or not participated(db, week.id, user_id):
        return
    stamp_rules.on_running_week_course_completed(db, user_id, week.id, course_id, run_id)
    coupon_rules.on_course_completed(db, user_id, course_id, run_id)
    bingo.grant_rewards(db, user_id, week, run_id)

