"""운영자 전용 회원 조회 API — 목록/상세.

가입 회원의 기본정보와 완주(스탬프) 현황을 운영자가 조회한다. **조회 전용**이다 —
이용 제한(제재)·상태 표시·감사 로그·러닝 기록은 이번 범위가 아니다(제재와 함께
추후). 그래서 User 스키마도 건드리지 않는다.

완주 코스 = 완주 인증(verifications)을 통과한 코스. 스탬프는 코스와 분리됐다(#71) —
코스 완주 말고도 받는 스탬프가 있어 "획득한 스탬프"와 "완주한 코스"는 다른 데이터다.

주의(활동 테이블 조인): Run.user_id는 users.id(UUID)로 가는 FK가 아니라 토큰
sub(=UUID 문자열)의 복사본(String)이다. 그래서 유저↔완주 매칭은 users.id를 문자열로
바꿔 runs.user_id와 비교한다(courses._completed_counts와 같은 방식).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Course, Run, User, UserLog, Verification
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
    """유저별 완주한 코스 수를 한 번에 조회한다(목록에서 N+1을 피하려고).

    courses._completed_counts와 같은 배치 패턴이되, 키가 코스가 아니라 유저다.
    """
    if not user_id_strs:
        return {}

    rows = db.execute(
        select(Run.user_id, func.count(func.distinct(Verification.course_id)))
        .join(Verification, Verification.run_id == Run.id)
        .where(Run.user_id.in_(user_id_strs), Verification.status == "matched")
        .group_by(Run.user_id)
    ).all()

    return {user_id: count for user_id, count in rows}


def _latest_platforms(db: Session, user_id_strs: list[str]) -> dict[str, str]:
    """유저별 최근 기기 종류(ios/android). users에는 없어서 그 유저의 가장 최근 행동
    로그에 찍힌 platform을 쓴다. 로그가 없으면 빠진다(→ None)."""
    if not user_id_strs:
        return {}

    rows = db.execute(
        select(UserLog.user_id, UserLog.platform)
        .distinct(UserLog.user_id)
        .where(UserLog.user_id.in_(user_id_strs), UserLog.platform.is_not(None))
        .order_by(UserLog.user_id, UserLog.created_at.desc())
    ).all()

    return {user_id: platform for user_id, platform in rows}


def _latest_devices(db: Session, user_id_strs: list[str]) -> dict[str, str]:
    """유저별 최근 기기 모델. 앱이 app_open·login 로그 detail.device에 싣는다."""
    if not user_id_strs:
        return {}

    device = UserLog.detail["device"].astext
    rows = db.execute(
        select(UserLog.user_id, device)
        .distinct(UserLog.user_id)
        .where(
            UserLog.user_id.in_(user_id_strs),
            UserLog.log_name.in_(("app_open", "login")),
            device.is_not(None),
        )
        .order_by(UserLog.user_id, UserLog.created_at.desc())
    ).all()

    return {user_id: model for user_id, model in rows}


def _completed_courses(db: Session, user: User) -> list[dict]:
    """이 유저가 완주한 코스 목록(코스명 포함, 최신순). 같은 코스를 여러 번 완주했으면
    처음 완주한 시각 하나만 — 예전 스탬프 기준 목록과 같은 모양이다.
    """
    first_completed = func.min(Verification.completed_at)
    rows = db.execute(
        select(Course.id, Course.name, first_completed)
        .join(Verification, Verification.course_id == Course.id)
        .join(Run, Run.id == Verification.run_id)
        .where(Run.user_id == str(user.id), Verification.status == "matched")
        .group_by(Course.id, Course.name)
        .order_by(first_completed.desc())
    ).all()

    return [
        {"course_id": course_id, "name": name, "acquired_at": acquired_at}
        for course_id, name, acquired_at in rows
    ]


def _to_summary(
    user: User, completed_count: int, platform: str | None, device: str | None
) -> dict:
    return {
        "id": user.id,
        "nickname": user.nickname,
        "providers": _providers(user),
        "email": user.email,
        "platform": platform,
        "device": device,
        "created_at": user.created_at,
        "last_login_at": user.last_login_at,
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

    ids = [str(u.id) for u in users]
    counts = _completed_counts(db, ids)
    platforms = _latest_platforms(db, ids)
    devices = _latest_devices(db, ids)

    return {
        "total": total,
        "items": [
            _to_summary(
                u,
                counts.get(str(u.id), 0),
                platforms.get(str(u.id)),
                devices.get(str(u.id)),
            )
            for u in users
        ],
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
        "platform": _latest_platforms(db, [str(user.id)]).get(str(user.id)),
        "device": _latest_devices(db, [str(user.id)]).get(str(user.id)),
        "profile_image_url": user.profile_image_url,
        "created_at": user.created_at,
        "last_login_at": user.last_login_at,
        "completed_count": len(courses),
        "completed_courses": courses,
    }
