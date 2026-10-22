"""운영자 전용 스탬프 종류 API — 목록/수정 + 도안. 앱 조회는 app.routers.stamps에 있다.

스탬프 종류는 여기서 만들지 않는다 — 코스 등록 때 코스 스탬프가 하나 생기고, 그 밖의 종류는
개발자가 DB에 직접 넣는다. 수정도 표시 정보만이고 지급 조건은 바꾸지 않는다.
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
from app.models import Stamp, StampDefinition
from app.schemas import AdminStampDefinitionOut, StampDefinitionUpdate

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


@router.patch("/stamps/{stamp_id}", response_model=AdminStampDefinitionOut)
def update_stamp_definition(
    stamp_id: uuid.UUID,
    payload: StampDefinitionUpdate,
    db: Session = Depends(get_db),
):
    """표시 정보만 고친다. 지급 조건(condition_type/params)은 운영툴에서 바꾸지 않는다."""
    definition = _load_or_404(db, stamp_id)
    definition.name = payload.name
    definition.description = payload.description
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
