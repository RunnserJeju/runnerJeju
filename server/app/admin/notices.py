"""운영자 전용 공지 API — 작성/목록/수정/삭제. 공개 조회는 app.routers.notices에 있다.

공개 GET /notices는 지금 노출 중인 공지만 보여줘서 운영자가 예약(미래)·만료 공지를
관리할 수 없다. 그래서 전체를 보는 GET /admin/notices를 따로 둔다(코스의
GET /admin/courses와 같은 이유).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Notice
from app.schemas import NoticeCreate, NoticeOut, NoticeUpdate

router = APIRouter(tags=["notices"])


def _load_notice_or_404(db: Session, notice_id: uuid.UUID) -> Notice:
    notice = db.get(Notice, notice_id)
    if notice is None:
        raise HTTPException(status_code=404, detail="공지를 찾을 수 없어요.")
    return notice


@router.get("/notices", response_model=list[NoticeOut])
def list_all_notices(db: Session = Depends(get_db)):
    """공지 전체 목록(예약·만료 포함). (관리자 전용 — 라우터 레벨에서 강제)

    노출 기간과 무관하게 다 내려준다 — 운영자는 아직 시작 안 한 공지나 끝난 공지도
    보고 고쳐야 하기 때문이다.
    """
    return list(
        db.execute(select(Notice).order_by(Notice.created_at.desc())).scalars()
    )


@router.post("/notices", response_model=NoticeOut, status_code=201)
def create_notice(
    payload: NoticeCreate,
    db: Session = Depends(get_db),
):
    """공지를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = Notice(
        title=payload.title,
        body=payload.body,
        category=payload.category,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
    )

    db.add(notice)
    db.commit()
    db.refresh(notice)

    return notice


@router.patch("/notices/{notice_id}", response_model=NoticeOut)
def update_notice(
    notice_id: uuid.UUID,
    payload: NoticeUpdate,
    db: Session = Depends(get_db),
):
    """공지를 수정한다(전체 교체). (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = _load_notice_or_404(db, notice_id)

    notice.title = payload.title
    notice.body = payload.body
    notice.category = payload.category
    notice.starts_at = payload.starts_at
    notice.ends_at = payload.ends_at

    db.commit()
    db.refresh(notice)

    return notice


@router.delete("/notices/{notice_id}", status_code=204)
def delete_notice(
    notice_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    """공지를 삭제한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = _load_notice_or_404(db, notice_id)
    db.delete(notice)
    db.commit()
