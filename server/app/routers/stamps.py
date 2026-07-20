import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Stamp
from app.schemas import StampOut

router = APIRouter(tags=["stamps"])


def _to_out(stamp: Stamp) -> dict:
    return {
        "id": stamp.id,
        "course_id": stamp.course_id,
        "course_name": stamp.course.name,
        "region": stamp.course.region,
        "acquired_at": stamp.acquired_at,
        "image_url": stamp.image_url,
        "record_id": stamp.run_id,
    }


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
