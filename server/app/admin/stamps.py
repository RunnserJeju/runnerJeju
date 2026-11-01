"""운영자 전용 스탬프 종류 API — 목록/수정 + 도안. 앱 조회는 app.routers.stamps에 있다.

스탬프 종류는 여기서 만들지 않는다 — 코스 등록 때 코스 스탬프가 하나 생기고, 그 밖의 종류는
개발자가 DB에 직접 넣는다. 수정도 표시 정보만이고 지급 조건은 바꾸지 않는다.
스탬프 종류는 지우지 않는다. 발급 기록(stamps)이 가리키므로 노출(is_active)을 끈다.
도안은 텍스트 폼(JSON)과 파일(multipart)을 섞지 않으려고 PUT/DELETE
/stamps/{id}/image로 분리했다(공지 배너와 같은 방식).
"""

import time
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import Stamp, StampDefinition
from app.routers.stamps import course_id_of
from app.schemas import AdminStampDefinitionOut, StampDefinitionUpdate
from app.stamp_images import course_categories, resolve_image_url

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


def _to_out(
    definition: StampDefinition, issued_count: int, category: str | None
) -> AdminStampDefinitionOut:
    out = AdminStampDefinitionOut.model_validate(definition)
    out.issued_count = issued_count
    out.display_image_url = resolve_image_url(definition, category)
    return out


def _category_of(db: Session, definition: StampDefinition) -> str | None:
    course_id = course_id_of(definition)
    if course_id is None:
        return None
    return course_categories(db, [course_id]).get(course_id)


def _single_out(db: Session, definition: StampDefinition) -> AdminStampDefinitionOut:
    return _to_out(
        definition,
        _issued_counts(db, [definition.id]).get(definition.id, 0),
        _category_of(db, definition),
    )


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
    categories = course_categories(
        db, {cid for d in definitions if (cid := course_id_of(d)) is not None}
    )
    return [
        _to_out(d, counts.get(d.id, 0), categories.get(course_id_of(d)))
        for d in definitions
    ]


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
    return _single_out(db, definition)


def _fixed_path(definition: StampDefinition, extension: str) -> str:
    """도안을 올릴 고정 경로. 스탬프마다 한 파일이고 교체는 같은 자리에 덮어쓴다.

    이미 버킷 안 폴더(`runningweek/{코스}`, `stamps/…`)에 있으면 그 이름을 지킨다 — 사람이
    알아볼 수 있게 붙인 이름이다. 아니면 `stamps/{id}`. 루트의 uuid 파일은 옛 방식이라 옮긴다.
    """
    current = storage.object_path(definition.image_url or "", bucket=storage.SUPABASE_STAMP_BUCKET)
    if current and "/" in current:
        return current.rsplit(".", 1)[0] + f".{extension}"
    return f"stamps/{definition.id}.{extension}"


@router.put("/stamps/{stamp_id}/image", response_model=AdminStampDefinitionOut)
def set_stamp_image(
    stamp_id: uuid.UUID,
    file: UploadFile = File(..., description="스탬프 도안 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """도안을 올린다(교체 포함). 고정 경로에 덮어쓰고 URL에 `?v=시각`을 붙여 캐시를 깬다.
    경로가 바뀌는 경우(확장자 변경, 옛 uuid 파일)에만 옛 파일을 지운다."""
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

    path = _fixed_path(definition, extension)
    try:
        new_url = storage.upload_fixed(
            content, path=path, content_type=file.content_type, bucket=storage.SUPABASE_STAMP_BUCKET
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    old_url = definition.image_url
    definition.image_url = f"{new_url}?v={int(time.time())}"
    db.commit()
    db.refresh(definition)
    if old_url and storage.object_path(old_url, bucket=storage.SUPABASE_STAMP_BUCKET) != path:
        storage.delete_image(old_url, bucket=storage.SUPABASE_STAMP_BUCKET)
    return _single_out(db, definition)


@router.delete("/stamps/{stamp_id}/image", response_model=AdminStampDefinitionOut)
def delete_stamp_image(stamp_id: uuid.UUID, db: Session = Depends(get_db)):
    """도안을 뗀다. 스탬프마다 파일이 하나뿐이라 Storage 파일도 지운다(실패는 무시)."""
    definition = _load_or_404(db, stamp_id)
    if definition.image_url:
        old_url = definition.image_url
        definition.image_url = None
        db.commit()
        db.refresh(definition)
        storage.delete_image(old_url, bucket=storage.SUPABASE_STAMP_BUCKET)
    return _single_out(db, definition)
