from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Notice
from app.schemas import NoticeOut

router = APIRouter(tags=["notices"])


def _is_visible(notice: Notice, now: datetime) -> bool:
    """지금 시각이 공지의 노출 기간 안이면 True.

    starts_at/ends_at은 각각 null이면 "제한 없음"이다 — starts_at=None은 즉시부터,
    ends_at=None은 무기한. 운영자가 예약(미래 시작)했거나 만료된 공지는 앱에 안 뜬다.
    """
    if notice.starts_at is not None and notice.starts_at > now:
        return False
    if notice.ends_at is not None and notice.ends_at < now:
        return False
    return True


@router.get("/notices", response_model=list[NoticeOut])
def list_notices(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """앱에 노출할 공지 목록. 지금 노출 기간 안인 것만 최신순으로 내린다.

    필터링을 SQL이 아니라 파이썬에서 하는 건 공지가 소량(배너처럼 전량 로드)이라
    비용이 없고, 노출 규칙(_is_visible)을 DB 없이도 그대로 테스트할 수 있어서다.
    운영자가 예약·만료 공지까지 보는 관리 목록은 GET /admin/notices에 있다.
    """
    now = datetime.now(timezone.utc)
    notices = db.execute(
        select(Notice).order_by(Notice.created_at.desc())
    ).scalars()
    return [notice for notice in notices if _is_visible(notice, now)]
