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

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import String, cast, func, or_, select
from sqlalchemy.orm import Session

from app.admin import audit
from app.admin.auth import require_admin_session
from app.admin.coupons import _effective_status
from app.db import get_db
from app.models import (
    AdminAction,
    AdminUser,
    Coupon,
    CouponDraw,
    Course,
    Partner,
    Run,
    Stamp,
    StampDefinition,
    User,
    UserCoupon,
    UserLog,
    Verification,
)
from app.routers.stamps import course_id_of
from app.schemas import (
    AdminActionOut,
    AdminRevokeRequest,
    UserCouponsOut,
    UserDetailOut,
    UserListOut,
    UserStampOut,
)
from app.stamp_images import course_categories, resolve_image_url

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


# 목록 정렬 가능 열. completed_count는 유저별 완주 코스 수 서브쿼리.
_completed_count_sq = (
    select(func.count(func.distinct(Verification.course_id)))
    .select_from(Run)
    .join(Verification, Verification.run_id == Run.id)
    .where(Run.user_id == cast(User.id, String), Verification.status == "matched")
    .correlate(User)
    .scalar_subquery()
)
_SORT_COLUMNS = {
    "nickname": User.nickname,
    "email": User.email,
    "created_at": User.created_at,
    "last_login_at": User.last_login_at,
    "completed_count": _completed_count_sq,
}


@router.get("/users", response_model=UserListOut)
def list_users(
    keyword: str | None = Query(default=None),
    sort: str = Query(default="created_at", pattern="^(nickname|email|created_at|last_login_at|completed_count)$"),
    order: str = Query(default="desc", pattern="^(asc|desc)$"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """회원 목록. (관리자 전용 — 라우터 레벨에서 강제)

    검색은 닉네임·이메일 부분일치, 정렬은 sort/order(기본 가입일 최신순). 빈 값은 방향과
    무관하게 뒤로 보내고, 같은 값이면 id로 tie-break 해서 페이지 경계가 흔들리지 않게 한다.
    페이지네이션은 offset/limit.

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
    col = _SORT_COLUMNS[sort]
    primary = col.asc().nulls_last() if order == "asc" else col.desc().nulls_last()
    stmt = stmt.order_by(primary, User.id.desc()).limit(limit).offset(offset)
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
    user = _load_user_or_404(db, user_id)

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


def _load_user_or_404(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=404, detail="회원을 찾을 수 없어요.")
    return user


@router.get("/users/{user_id}/stamps", response_model=list[UserStampOut])
def get_user_stamps(user_id: uuid.UUID, db: Session = Depends(get_db)):
    """회원 상세의 보유 스탬프 — 받은 순서 최신 먼저. 조회 전용(지급은 스탬프 페이지). (관리자 전용)"""
    user = _load_user_or_404(db, user_id)
    rows = db.execute(
        select(Stamp, StampDefinition)
        .join(StampDefinition, StampDefinition.id == Stamp.stamp_definition_id)
        .where(Stamp.user_id == str(user.id))
        .order_by(Stamp.acquired_at.desc(), Stamp.id.desc())
    ).all()
    categories = course_categories(
        db, {cid for _, d in rows if (cid := course_id_of(d)) is not None}
    )
    return [
        {
            "id": stamp.id,
            "stamp_definition_id": d.id,
            "name": d.name,
            "display_image_url": resolve_image_url(d, categories.get(course_id_of(d))),
            "acquired_at": stamp.acquired_at,
            "from_run": stamp.run_id is not None,
        }
        for stamp, d in rows
    ]


@router.get("/users/{user_id}/coupons", response_model=UserCouponsOut)
def get_user_coupons(user_id: uuid.UUID, db: Session = Depends(get_db)):
    """회원 상세 쿠폰 섹션 — 보유 중(사용가능·만료) / 사용 이력 / 추첨 이력. (관리자 전용)

    한 회원이 가진 쿠폰은 많지 않아 페이지 없이 전부 준다. user_coupons.user_id는
    str(users.id)라 문자열로 비교한다.
    """
    user = _load_user_or_404(db, user_id)
    uid = str(user.id)
    now = datetime.now(timezone.utc)

    rows = db.execute(
        select(UserCoupon, Coupon, Partner.name)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .outerjoin(Partner, Partner.id == UserCoupon.used_partner_id)
        .where(UserCoupon.user_id == uid)
        .order_by(UserCoupon.issued_at.desc(), UserCoupon.id.desc())
    ).all()

    held, used = [], []
    for uc, coupon, partner_name in rows:
        status = _effective_status(
            uc.used_at, coupon.valid_until, now, uc.expired_at, uc.revoked_at
        )
        row = {
            "id": uc.id,
            "code": uc.code,
            "coupon_id": coupon.id,
            "coupon_name": coupon.name,
            "benefit": coupon.benefit,
            "redeem_type": coupon.redeem_type,
            "grant_key": uc.grant_key,
            "issued_at": uc.issued_at,
            "used_at": uc.used_at,
            "valid_until": coupon.valid_until,
            "used_partner_name": partner_name,
            "status": status,
            "revoked_at": uc.revoked_at,
            "revoked_reason": uc.revoked_reason,
        }
        (used if status == "used" else held).append(row)
    # 사용 이력은 사용 시각 최신순.
    used.sort(key=lambda r: r["used_at"], reverse=True)

    draws = db.execute(
        select(CouponDraw, Coupon.name, UserCoupon.code)
        .join(Coupon, Coupon.id == CouponDraw.coupon_id)
        .outerjoin(UserCoupon, UserCoupon.id == CouponDraw.user_coupon_id)
        .where(CouponDraw.user_id == uid)
        .order_by(CouponDraw.drawn_at.desc(), CouponDraw.id.desc())
    ).all()

    return {
        "held": held,
        "used": used,
        "draws": [
            {
                "id": d.id,
                "coupon_id": d.coupon_id,
                "coupon_name": name,
                "grant_key": d.grant_key,
                "result": d.result,
                "code": code,
                "drawn_at": d.drawn_at,
            }
            for d, name, code in draws
        ],
    }


# --- 회수 · 운영 처리 이력 ------------------------------------------------------
# 회수는 한 건씩만 한다. 연쇄 회수(스탬프를 빼면 빙고 보상도 빼기)는 하지 않는다 — 이미
# 안내가 나간 리워드까지 사라지면 운영 사고라, 필요하면 운영자가 하나씩 더 회수한다.


@router.post("/users/{user_id}/stamps/{stamp_id}/revoke", status_code=204)
def revoke_stamp(
    user_id: uuid.UUID,
    stamp_id: uuid.UUID,
    payload: AdminRevokeRequest,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin_session),
):
    """스탬프 한 개를 회수(삭제)한다. 빙고판은 스탬프에서 계산하므로 칸도 함께 비워진다.
    이미 받은 빙고 줄 보상은 그대로 둔다."""
    user = _load_user_or_404(db, user_id)
    row = db.execute(
        select(Stamp, StampDefinition)
        .join(StampDefinition, StampDefinition.id == Stamp.stamp_definition_id)
        .where(Stamp.id == stamp_id, Stamp.user_id == str(user.id))
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="이 회원의 스탬프가 아니에요.")
    stamp, definition = row
    audit.record(
        db, admin, audit.STAMP_REVOKE,
        target_type="stamp", target_id=stamp.id, user_id=str(user.id),
        detail={
            "definition_id": str(definition.id),
            "name": definition.name,
            "from_run": stamp.run_id is not None,
            "reason": payload.reason,
        },
    )
    db.delete(stamp)
    db.commit()


@router.post("/users/{user_id}/coupons/{user_coupon_id}/revoke", status_code=204)
def revoke_coupon(
    user_id: uuid.UUID,
    user_coupon_id: uuid.UUID,
    payload: AdminRevokeRequest,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin_session),
):
    """쿠폰 한 장을 회수한다. 지우지 않고 revoked_at을 남겨 앱에서 사라지고 사용도 막힌다.
    이미 사용(지급완료)한 쿠폰은 되돌릴 수 없어 409. 추첨 기록은 그대로라 같은 조건으로
    다시 추첨되지는 않는다."""
    user = _load_user_or_404(db, user_id)
    row = db.execute(
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.id == user_coupon_id, UserCoupon.user_id == str(user.id))
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="이 회원의 쿠폰이 아니에요.")
    uc, coupon = row
    if uc.used_at is not None:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰은 회수할 수 없어요.")
    if uc.revoked_at is not None:
        raise HTTPException(status_code=409, detail="이미 회수된 쿠폰이에요.")
    uc.revoked_at = datetime.now(timezone.utc)
    uc.revoked_reason = payload.reason
    audit.record(
        db, admin, audit.COUPON_REVOKE,
        target_type="user_coupon", target_id=uc.id, user_id=str(user.id),
        detail={
            "coupon_id": str(coupon.id),
            "coupon_name": coupon.name,
            "code": uc.code,
            "grant_key": uc.grant_key,
            "reason": payload.reason,
        },
    )
    db.commit()


@router.get("/users/{user_id}/admin-actions", response_model=list[AdminActionOut])
def get_user_admin_actions(user_id: uuid.UUID, db: Session = Depends(get_db)):
    """이 회원에게 운영자가 한 처리(지급·회수·완주 인정·지급완료), 최신순 최대 100건."""
    user = _load_user_or_404(db, user_id)
    return list(
        db.execute(
            select(AdminAction)
            .where(AdminAction.user_id == str(user.id))
            .order_by(AdminAction.created_at.desc(), AdminAction.id.desc())
            .limit(100)
        ).scalars()
    )
