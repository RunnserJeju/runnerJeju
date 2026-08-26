from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Banner
from app.schemas import BannerOut

router = APIRouter(tags=["banners"])


@router.get("/banners", response_model=list[BannerOut])
def list_banners(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """홈 화면에 노출할 배너. 활성 상태만, 지정한 순서대로 내려준다."""
    stmt = (
        select(Banner)
        .where(Banner.is_active.is_(True))
        .order_by(Banner.sort_order, Banner.created_at)
    )
    return list(db.execute(stmt).scalars())
