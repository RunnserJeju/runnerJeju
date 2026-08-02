from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id, require_admin
from app.models import Notice
from app.schemas import NoticeCreate, NoticeOut

router = APIRouter(tags=["notices"])


@router.get("/notices", response_model=list[NoticeOut])
def list_notices(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    return list(
        db.execute(select(Notice).order_by(Notice.created_at.desc())).scalars()
    )


@router.post("/notices", response_model=NoticeOut, status_code=201)
def create_notice(
    payload: NoticeCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(require_admin),
):
    notice = Notice(title=payload.title, body=payload.body)

    db.add(notice)
    db.commit()
    db.refresh(notice)

    return notice
