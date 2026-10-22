"""러닝위크 도메인. 러닝위크 기간에만 도는 보상(쿠폰·빙고)은 전부 여기 진입점에서 시작한다.

- on_course_completed: 완주 인증 직후. 공개 중인 회차가 있을 때만 코스완료 쿠폰을 주고,
  참가자면 빙고 보상까지 판정한다.
- on_participated: 참가 신청 직후. 신청 전에 이미 채운 줄의 빙고 보상을 준다.

쿠폰·스탬프 발급 규칙(app.coupon_rules, app.stamp_rules)과 빙고 계산(app.bingo)은 기간을
모른다. 기간 판단은 이 모듈만 한다. 커밋은 부르는 쪽이 한다.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import bingo, coupon_rules
from app.models import RunningWeek, RunningWeekParticipation


def is_visible(week: RunningWeek, now: datetime) -> bool:
    """공지와 같은 규칙. 꺼져 있거나 공개 기간 밖이면 앱에 안 뜬다."""
    if not week.is_active:
        return False
    if week.starts_at is not None and week.starts_at > now:
        return False
    if week.ends_at is not None and week.ends_at < now:
        return False
    return True


def current_week(db: Session) -> RunningWeek | None:
    """지금 공개 중인 러닝위크. 여럿이면 가장 늦게 시작한 회차."""
    now = datetime.now(timezone.utc)
    weeks = db.execute(
        select(RunningWeek).order_by(
            RunningWeek.starts_at.desc().nulls_last(), RunningWeek.created_at.desc()
        )
    ).scalars()
    return next((week for week in weeks if is_visible(week, now)), None)


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


def on_course_completed(
    db: Session, user_id: str, course_id: uuid.UUID, run_id: uuid.UUID
) -> None:
    """완주 인증이 통과했을 때. 러닝위크가 아니면 아무것도 하지 않는다."""
    week = current_week(db)
    if week is None:
        return
    coupon_rules.on_course_completed(db, user_id, course_id, run_id)
    if participated(db, week.id, user_id):
        bingo.grant_rewards(db, user_id, week, run_id)


def on_participated(db: Session, user_id: str, week: RunningWeek) -> None:
    """참가 신청 직후. 신청 전에 채운 줄이 있으면 바로 준다."""
    bingo.grant_rewards(db, user_id, week, run_id=None)
