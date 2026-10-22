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
# 러닝위크 기간에 그 코스 완주. 회차·코스마다 하나이고 빙고 칸이 된다.
RUNNING_WEEK_COURSE = "running_week_course"
# 러닝위크 빙고판에서 N줄 이상 완성. 12줄(=판 전체)이 스페셜 스탬프다.
BINGO_LINES = "bingo_lines"
MANUAL = "manual"

# 조건 종류별 condition_params에 필요한 키. 운영툴 입력 검증에 쓴다.
CONDITION_TYPES: dict[str, tuple[str, ...]] = {
    COURSE_COMPLETE: ("course_id",),
    RUNNING_WEEK_COURSE: ("running_week_id", "course_id"),
    BINGO_LINES: ("running_week_id", "lines"),
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


def running_week_course_definitions(
    db: Session, week_id: uuid.UUID
) -> list[StampDefinition]:
    """이 회차 전용 코스 스탬프(노출 여부 무관)."""
    return list(
        db.execute(
            select(StampDefinition).where(
                StampDefinition.condition_type == RUNNING_WEEK_COURSE,
                StampDefinition.condition_params["running_week_id"].astext == str(week_id),
            )
        ).scalars()
    )


def on_running_week_course_completed(
    db: Session, user_id: str, week_id: uuid.UUID, course_id: uuid.UUID, run_id: uuid.UUID
) -> None:
    """러닝위크 기간에 코스를 완주했을 때. 이 회차·코스의 전용 스탬프를 발급한다.
    기간 판단은 부르는 쪽(app.running_week)이 한다."""
    for definition in running_week_course_definitions(db, week_id):
        if definition.is_active and definition.condition_params["course_id"] == str(course_id):
            _grant(db, user_id, definition, run_id=run_id)


def bingo_line_definitions(db: Session, week_id: uuid.UUID) -> list[StampDefinition]:
    """이 회차 빙고 줄 수를 조건으로 가진 스탬프 종류(노출 여부 무관)."""
    return list(
        db.execute(
            select(StampDefinition).where(
                StampDefinition.condition_type == BINGO_LINES,
                StampDefinition.condition_params["running_week_id"].astext == str(week_id),
            )
        ).scalars()
    )


def on_bingo_progress(
    db: Session, user_id: str, week_id: uuid.UUID, lines: int, run_id: uuid.UUID | None
) -> None:
    """빙고 줄 수가 lines일 때. 기준 줄 수 이하인 빙고 스탬프를 모두 발급한다 — 한 번에
    두 줄이 생겨도 사이 단계를 건너뛰지 않는다."""
    for definition in bingo_line_definitions(db, week_id):
        if definition.is_active and int(definition.condition_params["lines"]) <= lines:
            _grant(db, user_id, definition, run_id=run_id)


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
