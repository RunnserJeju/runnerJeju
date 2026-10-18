"""스탬프 획득 판정. 조건 종류마다 판정을 여기에 한 번만 쓴다.

스탬프 종류(StampDefinition)는 condition_type + condition_params를 데이터로 갖는다.
새 스탬프가 기존 종류로 표현되면 운영툴에서 행만 추가한다. 새로운 종류의 조건이
필요할 때만 CONDITION_TYPES와 판정 함수를 더한다.

발급은 (사용자, 스탬프 종류) 유일 제약에 기대어 멱등이다 — 같은 판정을 여러 번
돌려도 한 번만 발급된다.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Run, Stamp, StampDefinition

COURSE_COMPLETE = "course_complete"
MANUAL = "manual"

# 조건 종류별 condition_params에 필요한 키. 운영툴 입력 검증에 쓴다.
CONDITION_TYPES: dict[str, tuple[str, ...]] = {
    COURSE_COMPLETE: ("course_id",),
    MANUAL: (),
}


def course_condition(course_id: uuid.UUID):
    """이 코스 완주를 조건으로 가진 스탬프 종류를 고르는 WHERE 절(노출 여부 무관)."""
    return (
        StampDefinition.condition_type == COURSE_COMPLETE,
        StampDefinition.condition_params["course_id"].astext == str(course_id),
    )


def course_stamp_definitions(db: Session, course_id: uuid.UUID) -> list[StampDefinition]:
    """이 코스 완주를 조건으로 가진 스탬프 종류(노출 중인 것)."""
    return list(
        db.execute(
            select(StampDefinition).where(
                *course_condition(course_id), StampDefinition.is_active.is_(True)
            )
        ).scalars()
    )


def on_course_completed(db: Session, user_id: str, run: Run, course_id: uuid.UUID) -> None:
    """완주 인증이 통과했을 때. 이 코스를 조건으로 가진 스탬프를 발급한다."""
    for definition in course_stamp_definitions(db, course_id):
        _grant(db, user_id, definition, run_id=run.id)


def _grant(
    db: Session, user_id: str, definition: StampDefinition, *, run_id: uuid.UUID | None
) -> None:
    existing = db.execute(
        select(Stamp.id).where(
            Stamp.user_id == user_id, Stamp.stamp_definition_id == definition.id
        )
    ).scalar_one_or_none()
    if existing is not None:
        return
    db.add(Stamp(user_id=user_id, stamp_definition_id=definition.id, run_id=run_id))
