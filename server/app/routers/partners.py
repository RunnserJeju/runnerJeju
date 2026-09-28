"""앱용 협력업체 조회. 등록·수정은 운영 웹(app.admin.partners)에서 한다.

코스 응답에도 연결된 업체가 실려 오지만, 러닝 탭의 "협력업체" 모드는 코스와 무관하게
전체 업체를 지도에 찍고 목록으로 보여줘야 해서 따로 둔다.
"""

import uuid
from collections import defaultdict

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import Course, CoursePartner, Partner
from app.routers.courses import visible_courses
from app.schemas import PartnerCourseRef, PartnerSummary, PartnerWithCourses

router = APIRouter(tags=["partners"])


@router.get("/partners", response_model=list[PartnerWithCourses])
def list_partners(
    db: Session = Depends(get_db),
    _user_id: str = Depends(current_user_id),
    is_admin: bool = Depends(current_user_is_admin),
):
    """협력업체 전체(이름순)와 각 업체에 연결된 코스.

    연결 코스는 코스 목록과 같은 공개 규칙(visible_courses)을 따른다 — 일반 사용자에게
    admin 전용 코스로 넘어가는 버튼이 생기지 않게. 업체 자체는 공개 코스에 안 걸려
    있어도 보여준다(지도에서 협력업체만 둘러볼 수도 있다).
    """
    partners = list(db.execute(select(Partner).order_by(Partner.name)).scalars())

    links = db.execute(
        visible_courses(
            select(CoursePartner.partner_id, Course.id, Course.name).join(
                Course, Course.id == CoursePartner.course_id
            ),
            is_admin,
        ).order_by(Course.name)
    ).all()
    courses_by_partner: dict[uuid.UUID, list[PartnerCourseRef]] = defaultdict(list)
    for partner_id, course_id, course_name in links:
        courses_by_partner[partner_id].append(PartnerCourseRef(id=course_id, name=course_name))

    return [
        PartnerWithCourses(
            **PartnerSummary.model_validate(partner).model_dump(),
            courses=courses_by_partner.get(partner.id, []),
        )
        for partner in partners
    ]
