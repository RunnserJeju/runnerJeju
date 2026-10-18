"""운영자 전용 스탬프 종류 API — 목록/등록/수정 + 도안. 앱 조회는 app.routers.stamps에 있다.

스탬프 종류는 지우지 않는다. 발급 기록(stamps)이 가리키므로 노출(is_active)을 끈다.
도안은 텍스트 폼(JSON)과 파일(multipart)을 섞지 않으려고 PUT/DELETE
/stamps/{id}/image로 분리했다(공지 배너와 같은 방식).
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import Course, Stamp, StampDefinition
from app.schemas import (
    AdminStampDefinitionOut,
    StampDefinitionCreate,
    StampDefinitionUpdate,
)
from app.stamp_rules import COURSE_COMPLETE, CONDITION_TYPES

router = APIRouter(tags=["stamps"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


def _load_or_404(db: Session, stamp_id: uuid.UUID) -> StampDefinition:
    definition = db.get(StampDefinition, stamp_id)
    if definition is None:
        raise HTTPException(status_code=404, detail="스탬프를 찾을 수 없어요.")
    return definition


def _issued_counts(db: Session, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    rows = db.execute(
        select(Stamp.stamp_definition_id, func.count(Stamp.id))
        .where(Stamp.stamp_definition_id.in_(ids))
        .group_by(Stamp.stamp_definition_id)
    ).all()
    return {definition_id: count for definition_id, count in rows}


def _to_out(definition: StampDefinition, issued_count: int) -> AdminStampDefinitionOut:
    out = AdminStampDefinitionOut.model_validate(definition)
    out.issued_count = issued_count
    return out


def _validated_params(db: Session, condition_type: str, params: dict) -> dict:
    """조건 종류에 필요한 값만 남긴다. course_complete면 코스가 실제로 있어야 한다."""
    required = CONDITION_TYPES.get(condition_type)
    if required is None:
        raise HTTPException(status_code=422, detail=f"알 수 없는 조건 종류예요: {condition_type}")

    missing = [key for key in required if not params.get(key)]
    if missing:
        raise HTTPException(status_code=422, detail=f"조건 값이 빠졌어요: {', '.join(missing)}")

    cleaned = {key: params[key] for key in required}
    if condition_type == COURSE_COMPLETE:
        try:
            course_id = uuid.UUID(str(cleaned["course_id"]))
        except ValueError:
            raise HTTPException(status_code=422, detail="코스 id 형식이 아니에요.") from None
        if db.get(Course, course_id) is None:
            raise HTTPException(status_code=422, detail="코스를 찾을 수 없어요.")
        cleaned["course_id"] = str(course_id)
    return cleaned


@router.get("/stamps", response_model=list[AdminStampDefinitionOut])
def list_stamp_definitions(db: Session = Depends(get_db)):
    """스탬프 종류 전체(노출 끈 것 포함). (관리자 전용 — 라우터 레벨에서 강제)"""
    definitions = list(
        db.execute(
            select(StampDefinition).order_by(
                StampDefinition.sort_order, StampDefinition.created_at
            )
        ).scalars()
    )
    counts = _issued_counts(db, [d.id for d in definitions])
    return [_to_out(d, counts.get(d.id, 0)) for d in definitions]


@router.post("/stamps", response_model=AdminStampDefinitionOut, status_code=201)
def create_stamp_definition(payload: StampDefinitionCreate, db: Session = Depends(get_db)):
    definition = StampDefinition(
        name=payload.name,
        description=payload.description,
        condition_type=payload.condition_type,
        condition_params=_validated_params(db, payload.condition_type, payload.condition_params),
        is_active=payload.is_active,
        sort_order=payload.sort_order,
    )
    db.add(definition)
    db.commit()
    db.refresh(definition)
    return _to_out(definition, 0)


@router.patch("/stamps/{stamp_id}", response_model=AdminStampDefinitionOut)
def update_stamp_definition(
    stamp_id: uuid.UUID,
    payload: StampDefinitionUpdate,
    db: Session = Depends(get_db),
):
    """수정. 조건을 바꿔도 이미 발급된 스탬프는 그대로 둔다."""
    definition = _load_or_404(db, stamp_id)
    definition.name = payload.name
    definition.description = payload.description
    definition.condition_type = payload.condition_type
    definition.condition_params = _validated_params(
        db, payload.condition_type, payload.condition_params
    )
    definition.is_active = payload.is_active
    definition.sort_order = payload.sort_order
    db.commit()
    db.refresh(definition)
    return _to_out(definition, _issued_counts(db, [definition.id]).get(definition.id, 0))


@router.put("/stamps/{stamp_id}/image", response_model=AdminStampDefinitionOut)
def set_stamp_image(
    stamp_id: uuid.UUID,
    file: UploadFile = File(..., description="스탬프 도안 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """도안을 올린다(교체 포함).

    교체해도 옛 파일은 Storage에 남긴다 — 도안 하나를 여러 스탬프가 같이 쓰던
    시절의 파일이 있어(난이도별 도안) 지우면 다른 스탬프까지 깨진다.
    """
    definition = _load_or_404(db, stamp_id)

    extension = _ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")

    content = file.file.read(MAX_IMAGE_BYTES + 1)
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_IMAGE_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")

    try:
        new_url = storage.upload_image(
            content,
            content_type=file.content_type,
            extension=extension,
            bucket=storage.SUPABASE_STAMP_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    definition.image_url = new_url
    db.commit()
    db.refresh(definition)
    return _to_out(definition, _issued_counts(db, [definition.id]).get(definition.id, 0))


@router.delete("/stamps/{stamp_id}/image", response_model=AdminStampDefinitionOut)
def delete_stamp_image(stamp_id: uuid.UUID, db: Session = Depends(get_db)):
    """도안을 뗀다(컬럼만 NULL). Storage 파일은 지우지 않는다."""
    definition = _load_or_404(db, stamp_id)
    if definition.image_url:
        definition.image_url = None
        db.commit()
        db.refresh(definition)
    return _to_out(definition, _issued_counts(db, [definition.id]).get(definition.id, 0))
