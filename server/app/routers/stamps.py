import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import Course, Stamp, StampDefinition
from app.routers.courses import visible_courses
from app.schemas import StampDefinitionOut, StampOut
from app.stamp_rules import COURSE_COMPLETE

router = APIRouter(tags=["stamps"])


def course_id_of(definition: StampDefinition) -> uuid.UUID | None:
    """course_complete 스탬프의 코스. 그 밖의 종류는 None."""
    if definition.condition_type != COURSE_COMPLETE:
        return None
    raw = (definition.condition_params or {}).get("course_id")
    try:
        return uuid.UUID(str(raw)) if raw else None
    except ValueError:
        return None


def definition_to_out(definition: StampDefinition) -> dict:
    return {
        "id": definition.id,
        "name": definition.name,
        "description": definition.description,
        "image_url": definition.image_url,
        "condition_type": definition.condition_type,
        "course_id": course_id_of(definition),
        "sort_order": definition.sort_order,
    }


def _to_out(stamp: Stamp) -> dict:
    definition = stamp.definition
    return {
        "id": stamp.id,
        "stamp_definition_id": definition.id,
        "name": definition.name,
        "description": definition.description,
        # 도안은 스탬프 종류를 라이브로 참조한다 — 나중에 바꿔도 이미 딴 스탬프에 반영된다.
        "image_url": definition.image_url,
        "condition_type": definition.condition_type,
        "course_id": course_id_of(definition),
        "acquired_at": stamp.acquired_at,
        "record_id": stamp.run_id,
        "course_name": definition.name,
    }


@router.get("/stamp-definitions", response_model=list[StampDefinitionOut])
def list_stamp_definitions(
    db: Session = Depends(get_db),
    is_admin: bool = Depends(current_user_is_admin),
):
    """스탬프 탭이 그릴 스탬프 종류(노출 중인 것). 숨긴 코스의 완주 스탬프는 뺀다."""
    definitions = list(
        db.execute(
            select(StampDefinition)
            .where(StampDefinition.is_active.is_(True))
            .order_by(StampDefinition.sort_order, StampDefinition.created_at)
        ).scalars()
    )

    course_ids = {cid for d in definitions if (cid := course_id_of(d)) is not None}
    visible = (
        set(
            db.execute(
                visible_courses(select(Course.id).where(Course.id.in_(course_ids)), is_admin)
            ).scalars()
        )
        if course_ids
        else set()
    )

    return [
        definition_to_out(d)
        for d in definitions
        if d.condition_type != COURSE_COMPLETE or course_id_of(d) in visible
    ]


@router.get("/stamps", response_model=list[StampOut])
def list_stamps(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    stamps = db.execute(
        select(Stamp).where(Stamp.user_id == user_id).order_by(Stamp.acquired_at.desc())
    ).scalars()

    return [_to_out(stamp) for stamp in stamps]


@router.get("/stamps/{stamp_id}", response_model=StampOut)
def get_stamp(
    stamp_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    stamp = db.get(Stamp, stamp_id)
    if stamp is None or stamp.user_id != user_id:
        raise HTTPException(status_code=404, detail="스탬프를 찾을 수 없어요.")

    return _to_out(stamp)
