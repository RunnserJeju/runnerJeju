"""운영자 전용 공지 API — 등록. 공개 조회는 app.routers.notices에 있다."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Notice
from app.schemas import NoticeCreate, NoticeOut

router = APIRouter(tags=["notices"])


@router.post("/notices", response_model=NoticeOut, status_code=201)
def create_notice(
    payload: NoticeCreate,
    db: Session = Depends(get_db),
):
    """공지를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = Notice(title=payload.title, body=payload.body)

    db.add(notice)
    db.commit()
    db.refresh(notice)

    return notice
