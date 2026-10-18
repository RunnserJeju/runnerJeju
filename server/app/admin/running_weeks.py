"""운영자 전용 러닝위크 API — 회차 등록/수정, 배너 이미지, 빙고 배치, 참가자 조회.

앱 조회·참가 신청은 app.routers.running_weeks에 있다. 배너 이미지는 공지처럼 텍스트
폼(JSON)과 파일(multipart)을 섞지 않으려고 PUT/DELETE /running-weeks/{id}/image로 뗐다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import RunningWeek, RunningWeekParticipation, StampDefinition
from app.routers.running_weeks import purge_expired_participations
from app.schemas import (
    AdminParticipationOut,
    AdminRunningWeekOut,
    BingoUpdate,
    RunningWeekCreate,
    RunningWeekUpdate,
)

router = APIRouter(tags=["running-weeks"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


def _load_or_404(db: Session, week_id: uuid.UUID) -> RunningWeek:
    week = db.get(RunningWeek, week_id)
    if week is None:
        raise HTTPException(status_code=404, detail="러닝위크를 찾을 수 없어요.")
    return week


def _participant_counts(db: Session, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    rows = db.execute(
        select(RunningWeekParticipation.running_week_id, func.count())
        .where(RunningWeekParticipation.running_week_id.in_(ids))
        .group_by(RunningWeekParticipation.running_week_id)
    ).all()
    return {week_id: count for week_id, count in rows}


def _to_out(db: Session, week: RunningWeek) -> AdminRunningWeekOut:
    out = AdminRunningWeekOut.model_validate(week)
    out.participant_count = _participant_counts(db, [week.id]).get(week.id, 0)
    return out


def _apply(week: RunningWeek, payload: RunningWeekCreate) -> None:
    week.title = payload.title
    week.description = payload.description
    week.starts_at = payload.starts_at
    week.ends_at = payload.ends_at
    week.is_active = payload.is_active


@router.get("/running-weeks", response_model=list[AdminRunningWeekOut])
def list_running_weeks(db: Session = Depends(get_db)):
    """전체 회차(예약·종료·숨김 포함), 최신 등록순. (관리자 전용 — 라우터 레벨에서 강제)"""
    weeks = list(
        db.execute(select(RunningWeek).order_by(RunningWeek.created_at.desc())).scalars()
    )
    counts = _participant_counts(db, [w.id for w in weeks])
    result = []
    for week in weeks:
        out = AdminRunningWeekOut.model_validate(week)
        out.participant_count = counts.get(week.id, 0)
        result.append(out)
    return result


@router.post("/running-weeks", response_model=AdminRunningWeekOut, status_code=201)
def create_running_week(payload: RunningWeekCreate, db: Session = Depends(get_db)):
    week = RunningWeek(bingo_stamp_ids=[])
    _apply(week, payload)
    db.add(week)
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.patch("/running-weeks/{week_id}", response_model=AdminRunningWeekOut)
def update_running_week(
    week_id: uuid.UUID, payload: RunningWeekUpdate, db: Session = Depends(get_db)
):
    week = _load_or_404(db, week_id)
    _apply(week, payload)
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.put("/running-weeks/{week_id}/bingo", response_model=AdminRunningWeekOut)
def set_bingo(week_id: uuid.UUID, payload: BingoUpdate, db: Session = Depends(get_db)):
    """빙고 배치를 통째로 바꾼다. 25개 모두 실제 스탬프 종류여야 한다.

    배열 안 id에는 외래키가 없어서 여기서 확인한다. 숨긴 스탬프도 놓을 수는 있지만
    앱에는 빈 칸으로 보인다.
    """
    week = _load_or_404(db, week_id)
    found = set(
        db.execute(
            select(StampDefinition.id).where(StampDefinition.id.in_(payload.stamp_ids))
        ).scalars()
    )
    missing = [str(i) for i in payload.stamp_ids if i not in found]
    if missing:
        raise HTTPException(status_code=422, detail=f"없는 스탬프예요: {', '.join(missing)}")

    week.bingo_stamp_ids = [str(i) for i in payload.stamp_ids]
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.get(
    "/running-weeks/{week_id}/participations",
    response_model=list[AdminParticipationOut],
)
def list_participations(week_id: uuid.UUID, db: Session = Depends(get_db)):
    """참가자 목록(신청순). 보관 기간이 지난 행은 먼저 지운다."""
    _load_or_404(db, week_id)
    purge_expired_participations(db)
    return list(
        db.execute(
            select(RunningWeekParticipation)
            .where(RunningWeekParticipation.running_week_id == week_id)
            .order_by(RunningWeekParticipation.created_at)
        ).scalars()
    )


@router.put("/running-weeks/{week_id}/image", response_model=AdminRunningWeekOut)
def set_running_week_image(
    week_id: uuid.UUID,
    file: UploadFile = File(..., description="커뮤니티 배너 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """커뮤니티 상단 배너를 올린다(교체 포함). 옛 파일은 새로 올린 뒤 지운다(공지와 같다)."""
    week = _load_or_404(db, week_id)

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
            bucket=storage.SUPABASE_STORAGE_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    old_url = week.image_url
    week.image_url = new_url
    db.commit()
    db.refresh(week)

    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return _to_out(db, week)


@router.delete("/running-weeks/{week_id}/image", response_model=AdminRunningWeekOut)
def delete_running_week_image(week_id: uuid.UUID, db: Session = Depends(get_db)):
    week = _load_or_404(db, week_id)
    image_url = week.image_url
    if image_url:
        week.image_url = None
        db.commit()
        db.refresh(week)
        storage.delete_image(image_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return _to_out(db, week)
