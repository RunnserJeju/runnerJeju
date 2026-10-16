"""운영자 전용 홈 구성 API — 앱 홈 '러닝 코스 큐레이션'과 '추천 협력 업체'.

각 섹션에 띄울 항목(id + 설명 + detail)을 순서대로 담은 목록을 통째로 받아 교체한다
(course_curations / partner_curations). 조회는 앱과 같은 형태(HomeCurationOut)다.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Course, CourseCuration, Partner, PartnerCuration
from app.routers.home import load_curation
from app.schemas import HomeCurationItem, HomeCurationOut, HomeCurationPayload

router = APIRouter(prefix="/home", tags=["home"])


def _replace(
    db: Session, target, curation, key: str, items: list[HomeCurationItem], label: str
) -> None:
    ids = [item.id for item in items]
    if len(set(ids)) != len(ids):
        raise HTTPException(status_code=422, detail=f"같은 {label}이 두 번 들어 있어요.")

    # 없는 id가 섞이면 커밋 때 FK 위반(500)이 나므로 미리 422로 돌려준다.
    found = set(db.execute(select(target.id).where(target.id.in_(ids))).scalars()) if ids else set()
    missing = [str(id_) for id_ in ids if id_ not in found]
    if missing:
        raise HTTPException(
            status_code=422, detail=f"없는 {label}이 있어요: {', '.join(missing)}"
        )

    # 전부 지우고 새로 넣는다 — 한 트랜잭션이라 중간 상태는 안 보인다.
    db.execute(delete(curation))
    db.add_all(
        curation(
            **{key: item.id},
            sort_order=order,
            # 빈 문자열은 "없음"으로 저장한다 — 폼에서 칸을 지우면 null로 돌아가게.
            describe=(item.describe or "").strip() or None,
            detail=item.detail,
        )
        for order, item in enumerate(items)
    )
    db.commit()


@router.get("", response_model=HomeCurationOut)
def get_home(db: Session = Depends(get_db)):
    """현재 홈 구성. 공개 범위와 무관하게 고른 것 전부. (관리자 전용 — 라우터 레벨에서 강제)"""
    return load_curation(db)


@router.put("/courses", status_code=204)
def set_curation_courses(payload: HomeCurationPayload, db: Session = Depends(get_db)):
    """홈 '러닝 코스 큐레이션'을 교체한다. (관리자 전용 — 라우터 레벨에서 강제)

    공개 범위는 따지지 않는다 — 고른 코스가 비공개면 앱 코스 목록에 없으므로
    일반 사용자 홈에도 안 나온다.
    """
    _replace(db, Course, CourseCuration, "course_id", payload.items, "코스")


@router.put("/partners", status_code=204)
def set_featured_partners(payload: HomeCurationPayload, db: Session = Depends(get_db)):
    """홈 '추천 협력 업체'를 교체한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    _replace(db, Partner, PartnerCuration, "partner_id", payload.items, "협력업체")
