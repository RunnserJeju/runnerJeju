"""코스 완주의 정의. "누가 어느 코스를 완주했나"는 전부 여기를 본다.

완주는 두 곳에 남는다.
- 앱으로 달린 러닝: 통과한 검증(verifications, runs에 묶임). source는 'run'.
- 러닝 없이 인정된 완주: external_completions(가민·순토 링크, 운영자 수동 인정).
  source는 'garmin' | 'suunto' | 'admin'.
"""

import uuid

from sqlalchemy import literal, select, union_all
from sqlalchemy.orm import Session

from app.models import ExternalCompletion, Run, Verification

MATCHED = "matched"


def completions():
    """완주 한 건당 한 줄: user_id, course_id, completed_at, source. 같은 (사람, 코스)가
    여러 줄일 수 있다(재완주) — 세는 쪽이 distinct 한다."""
    by_run = (
        select(
            Run.user_id.label("user_id"),
            Verification.course_id.label("course_id"),
            Verification.completed_at.label("completed_at"),
            literal("run").label("source"),
        )
        .join(Run, Run.id == Verification.run_id)
        .where(Verification.status == MATCHED)
    )
    external = select(
        ExternalCompletion.user_id,
        ExternalCompletion.course_id,
        ExternalCompletion.created_at,
        ExternalCompletion.source,
    ).where(ExternalCompletion.status == MATCHED)
    return union_all(by_run, external).subquery("completions")


def is_completed(db: Session, user_id: str, course_id: uuid.UUID) -> bool:
    c = completions()
    return (
        db.execute(
            select(c.c.course_id).where(c.c.user_id == user_id, c.c.course_id == course_id).limit(1)
        ).first()
        is not None
    )
