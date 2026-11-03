"""앱 홈 구성 조회. 편집은 운영 웹(app.admin.home)에서 한다.

코스·협력업체 자체는 싣지 않는다 — 앱 홈은 코스 목록(GET /courses)과 협력업체 목록
(GET /partners)을 이미 받으므로, 여기서는 그중 무엇을 어떤 순서로 띄울지와 큐레이션
설명만 알려준다. 공개 범위도 따로 거르지 않는다: 일반 사용자에게 안 보이는 코스는
코스 목록에 없어서 앱이 이 id를 찾지 못하고 건너뛴다.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import CourseCuration, Partner, PartnerCuration
from app.routers.partners import visible_partners
from app.schemas import HomeCurationItem, HomeCurationOut

router = APIRouter(tags=["home"])


def load_curation(db: Session, *, is_admin: bool = True) -> HomeCurationOut:
    """두 섹션의 구성(고른 순서대로). 운영 웹 조회(app.admin.home)도 같이 쓴다.

    업체는 is_admin이 아니면 visibility='public'만 — 앱은 GET /partners에 없는 id를 못 그린다.
    코스 큐레이션은 지금처럼 전부 싣는다(앱이 코스 목록과 맞춰 거른다).
    """
    courses = db.execute(select(CourseCuration).order_by(CourseCuration.sort_order)).scalars()
    partners = db.execute(
        visible_partners(
            select(PartnerCuration).join(Partner, Partner.id == PartnerCuration.partner_id),
            is_admin,
        ).order_by(PartnerCuration.sort_order)
    ).scalars()
    return HomeCurationOut(
        courses=[
            HomeCurationItem(id=row.course_id, describe=row.describe, detail=row.detail or {})
            for row in courses
        ],
        partners=[
            HomeCurationItem(id=row.partner_id, describe=row.describe, detail=row.detail or {})
            for row in partners
        ],
    )


@router.get("/home/curation", response_model=HomeCurationOut)
def get_home_curation(
    db: Session = Depends(get_db),
    _user_id: str = Depends(current_user_id),
    is_admin: bool = Depends(current_user_is_admin),
):
    """홈 '러닝 코스 큐레이션'과 '추천 협력 업체'에 띄울 것(순서대로)."""
    return load_curation(db, is_admin=is_admin)
