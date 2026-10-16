"""앱 홈 구성 조회. 편집은 운영 웹(app.admin.home)에서 한다.

id 목록만 내린다 — 앱 홈은 코스 목록(GET /courses)과 협력업체 목록(GET /partners)을
이미 받으므로, 여기서는 그중 무엇을 어떤 순서로 띄울지만 알려준다. 공개 범위도
따로 거르지 않는다: 일반 사용자에게 안 보이는 코스는 코스 목록에 없어서 앱이 이
id를 찾지 못하고 건너뛴다.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import CourseCuration, PartnerCuration
from app.schemas import HomeCurationOut

router = APIRouter(tags=["home"])


def load_curation(db: Session) -> HomeCurationOut:
    """두 섹션의 구성(고른 순서대로). 운영 웹 조회(app.admin.home)도 같이 쓴다."""
    course_ids = db.execute(
        select(CourseCuration.course_id).order_by(CourseCuration.sort_order)
    ).scalars()
    partner_ids = db.execute(
        select(PartnerCuration.partner_id).order_by(PartnerCuration.sort_order)
    ).scalars()
    return HomeCurationOut(course_ids=list(course_ids), partner_ids=list(partner_ids))


@router.get("/home/curation", response_model=HomeCurationOut)
def get_home_curation(
    db: Session = Depends(get_db),
    _user_id: str = Depends(current_user_id),
):
    """홈 '러닝 코스 큐레이션'과 '추천 협력 업체'에 띄울 id(순서대로)."""
    return load_curation(db)
