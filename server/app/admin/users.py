"""운영자 전용 회원 조회 API — 목록/상세.

가입 회원의 기본정보와 완주(스탬프) 현황을 운영자가 조회한다. **조회 전용**이다 —
이용 제한(제재)·상태 표시·감사 로그·러닝 기록은 이번 범위가 아니다(제재와 함께
추후). 그래서 User 스키마도 건드리지 않는다.

완주 코스 = 획득 스탬프: 스탬프는 코스 완주로만, 유저·코스당 하나 발급된다
(uq_stamp_user_course). 그래서 "완주한 코스 목록"과 "획득한 스탬프"는 같은 데이터다.

주의(활동 테이블 조인): Stamp.user_id는 users.id(UUID)로 가는 FK가 아니라 토큰
sub(=UUID 문자열)의 복사본(String)이다. 그래서 유저↔완주 매칭은 users.id를 문자열로
바꿔 stamps.user_id와 비교한다(courses._completed_counts와 같은 방식). 반면
Stamp.course_id는 courses.id로 가는 진짜 UUID FK라 코스명은 단일 조인으로 가져온다.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Course, Stamp, User
from app.schemas import UserDetailOut, UserListOut

router = APIRouter(tags=["users"])


def _providers(user: User) -> list[str]:
    """가입에 쓰인 소셜 provider 종류. 보통 하나지만 여러 개가 연결됐을 수도 있어
    목록으로 준다. 내부 식별자(kakao_id 등) 원본은 노출하지 않는다."""
    result = []
    if user.kakao_id:
        result.append("kakao")
    if user.apple_id:
        result.append("apple")
    if user.google_id:
        result.append("google")
    return result


def _completed_counts(db: Session, user_id_strs: list[str]) -> dict[str, int]:
    """유저별 완주(스탬프) 수를 한 번에 조회한다(목록에서 N+1을 피하려고).

    courses._completed_counts와 같은 배치 패턴이되, 키가 코스가 아니라 유저다.
    """
    if not user_id_strs:
        return {}

    rows = db.execute(
        select(Stamp.user_id, func.count(Stamp.id))
        .where(Stamp.user_id.in_(user_id_strs))
        .group_by(Stamp.user_id)
    ).all()

    return {user_id: count for user_id, count in rows}


def _completed_courses(db: Session, user: User) -> list[dict]:
    """이 유저가 완주한 코스 목록(코스명 포함, 최신순).

    Stamp.course_id가 courses.id로 가는 FK라 단일 조인으로 코스명을 가져온다 —
    스탬프를 먼저 뽑고 코스를 하나씩 다시 조회하는 N+1을 만들지 않는다.
    """
    rows = db.execute(
        select(Course.id, Course.name, Stamp.acquired_at)
        .join(Course, Course.id == Stamp.course_id)
        .where(Stamp.user_id == str(user.id))
        .order_by(Stamp.acquired_at.desc())
    ).all()

    return [
        {"course_id": course_id, "name": name, "acquired_at": acquired_at}
        for course_id, name, acquired_at in rows
    ]


def _to_summary(user: User, completed_count: int) -> dict:
    return {
        "id": user.id,
        "nickname": user.nickname,
        "providers": _providers(user),
        "email": user.email,
        "created_at": user.created_at,
        "completed_count": completed_count,
    }


@router.get("/users", response_model=UserListOut)
def list_users(
    keyword: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """회원 목록. (관리자 전용 — 라우터 레벨에서 강제)

    검색은 닉네임·이메일 부분일치, 정렬은 가입일 최신순(같은 시각이면 id로 tie-break
    해서 페이지 경계가 흔들리지 않게 한다), 페이지네이션은 offset/limit.

    완주 수는 이 페이지 유저들만 한 번에 배치 집계한다(N+1 없음). total은 같은 필터의
    전체 개수로, 페이지 UI가 쓴다.
    """
    # 탈퇴(익명화)된 husk는 항상 제외한다. keyword 필터가 있으면 뒤에 덧붙는다.
    filters = [User.deleted_at.is_(None)]
    if keyword:
        like = f"%{keyword}%"
        filters.append(or_(User.nickname.ilike(like), User.email.ilike(like)))

    count_stmt = select(func.count()).select_from(User)
    if filters:
        count_stmt = count_stmt.where(*filters)
    total = db.scalar(count_stmt)

    stmt = select(User)
    if filters:
        stmt = stmt.where(*filters)
    stmt = (
        stmt.order_by(User.created_at.desc(), User.id.desc())
        .limit(limit)
        .offset(offset)
    )
    users = list(db.execute(stmt).scalars())

    counts = _completed_counts(db, [str(u.id) for u in users])

    return {
        "total": total,
        "items": [_to_summary(u, counts.get(str(u.id), 0)) for u in users],
    }


@router.get("/users/{user_id}", response_model=UserDetailOut)
def get_user(user_id: uuid.UUID, db: Session = Depends(get_db)):
    """회원 상세 — 기본정보 + 완주(스탬프) 코스 목록. (관리자 전용)

    완주 수는 완주 목록의 길이라 따로 집계하지 않는다.
    """
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=404, detail="회원을 찾을 수 없어요.")

    courses = _completed_courses(db, user)

    return {
        "id": user.id,
        "nickname": user.nickname,
        "providers": _providers(user),
        "email": user.email,
        "profile_image_url": user.profile_image_url,
        "created_at": user.created_at,
        "completed_count": len(courses),
        "completed_courses": courses,
    }
