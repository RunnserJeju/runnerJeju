"""쿠폰 자동 지급 판정. 지급 조건 종류마다 판정을 여기에 한 번만 쓴다.

쿠폰 템플릿(Coupon)은 trigger_type으로 지급 조건을 갖는다. 행은 마이그레이션이 심고
운영툴은 수정만 하므로, 새 조건이 생기면 여기 판정 함수와 행을 심는 마이그레이션을
같이 더한다(stamp_rules와 같은 방식).

지급은 전부 추첨이다(win_rate_percent, 100이면 확정). 추첨 결과는 CouponDraw에
(쿠폰, 사용자, grant_key)당 한 번 남겨 낙첨해도 같은 조건으로 다시 뽑지 않는다. 당첨 발급은
(쿠폰, 사용자, grant_key) 유일 제약으로도 막힌다. 러닝위크 기간인지는 모른다 — 자동 지급은
app.running_week 진입점을 거쳐서만 불린다.

재고(stock)가 있는 쿠폰은 템플릿 행을 FOR UPDATE로 잠근 뒤 기록 확인·발급 수 세기·발급을
한다. 읽기와 쓰기 사이에 다른 트랜잭션이 끼지 못하므로 수량을 넘겨 발급되지 않는다. 운영자
수동 발급(admin/coupons.issue_coupon)도 같은 lock_coupon → issue_with_stock을 탄다.
"""

import uuid
from datetime import datetime, timezone
from random import SystemRandom

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.models import Coupon, CouponDraw, UserCoupon

MANUAL = "manual"
COURSE_COMPLETE = "course_complete"
# 러닝위크 빙고판 25칸을 다 채움(=25개 코스 완주). '스페셜 쿠폰'.
BINGO_COMPLETE = "bingo_complete"
# 러닝위크 빙고 N줄 이상. trigger_params = {lines}. 1·3·5줄 행이 심겨 있다.
BINGO_LINES = "bingo_lines"

TRIGGER_TYPES: tuple[str, ...] = (MANUAL, COURSE_COMPLETE, BINGO_COMPLETE, BINGO_LINES)

# 앱에서 업체 번호를 입력해 사용완료 / 카카오톡 채널로 문의하고 운영자가 지급완료 처리.
REDEEM_PARTNER_PIN = "partner_pin"
REDEEM_KAKAO_CHANNEL = "kakao_channel"
REDEEM_TYPES: tuple[str, ...] = (REDEEM_PARTNER_PIN, REDEEM_KAKAO_CHANNEL)

DRAW_WON = "won"
DRAW_LOST = "lost"
DRAW_SOLD_OUT = "sold_out"

# 쿠폰 코드는 16진수 4자리("3F0A"). 말로 전달하기 쉬우라고 짧게 간다. 마이그레이션 0043의 백필과 같다.
CODE_LEN = 4
_CODE_ALPHABET = "0123456789ABCDEF"
_rng = SystemRandom()


def normalize_code(raw: str) -> str | None:
    """사람이 친 코드를 저장 형태로. 공백·하이픈 무시, 소문자 허용. 코드 꼴이 아니면 None."""
    code = raw.strip().upper().replace(" ", "").replace("-", "")
    if len(code) != CODE_LEN or any(ch not in _CODE_ALPHABET for ch in code):
        return None
    return code


def _fresh_codes(db: Session, n: int) -> list[str]:
    """아직 안 쓰인 코드 n개. 경우의 수가 65536뿐이라 한 번 조회해 겹치는 건 다시 뽑는다."""
    codes: list[str] = []
    for _ in range(20):
        if len(codes) >= n:
            return codes
        cand = {"".join(_rng.choice(_CODE_ALPHABET) for _ in range(CODE_LEN)) for _ in range(n - len(codes))}
        cand -= set(codes)
        taken = set(db.execute(select(UserCoupon.code).where(UserCoupon.code.in_(cand))).scalars())
        codes.extend(cand - taken)
    raise RuntimeError("쿠폰 코드를 더 만들 수 없어요. 코드 공간이 거의 찼어요.")


def course_grant_key(course_id: uuid.UUID) -> str:
    """코스완료 쿠폰의 중복 방지 키. 코스마다 한 번, 같은 코스 재완주는 추첨도 다시 없음."""
    return f"course:{course_id}"


def bingo_grant_key(week_id: uuid.UUID) -> str:
    """빙고판 완성 쿠폰의 중복 방지 키. 회차마다 한 번."""
    return f"bingo:{week_id}"


def bingo_lines_grant_key(week_id: uuid.UUID, lines: int) -> str:
    """빙고 줄 리워드의 중복 방지 키. 회차·기준 줄 수마다 한 번."""
    return f"bingo_lines:{week_id}:{lines}"


def lines_of(coupon: Coupon) -> int | None:
    """bingo_lines 쿠폰의 기준 줄 수. 다른 쿠폰은 None."""
    lines = (coupon.trigger_params or {}).get("lines")
    return int(lines) if lines is not None else None


def issued_count(db: Session, coupon_id: uuid.UUID) -> int:
    """지금까지 발급된 수(사용·만료·탈퇴분 포함). 재고의 원본은 이 행 수다."""
    return db.scalar(
        select(func.count()).select_from(UserCoupon).where(UserCoupon.coupon_id == coupon_id)
    ) or 0


def _usable(coupon: Coupon, now: datetime) -> bool:
    return coupon.is_active and (coupon.valid_until is None or coupon.valid_until > now)


def active_coupon(db: Session, trigger_type: str) -> Coupon | None:
    """이 조건으로 지급 중인 쿠폰. 꺼졌거나 유효기간이 지났으면 None. 심은 행이 하나뿐이라
    첫 것을 쓴다."""
    now = datetime.now(timezone.utc)
    return db.execute(
        select(Coupon)
        .where(
            Coupon.trigger_type == trigger_type,
            Coupon.is_active.is_(True),
            or_(Coupon.valid_until.is_(None), Coupon.valid_until > now),
        )
        .order_by(Coupon.created_at)
        .limit(1)
    ).scalar_one_or_none()


def lock_coupon(db: Session, coupon_id: uuid.UUID) -> Coupon | None:
    """템플릿 행을 FOR UPDATE로 잠가서 가져온다. 트랜잭션이 끝날 때까지 같은 행을 보는
    다른 발급·수정은 기다린다."""
    return db.execute(
        select(Coupon).where(Coupon.id == coupon_id).with_for_update()
    ).scalar_one_or_none()


def issue_with_stock(
    db: Session,
    coupon: Coupon,
    user_ids: list[str],
    *,
    grant_key: str | None = None,
    run_id: uuid.UUID | None = None,
) -> list[UserCoupon]:
    """재고를 세고 발급한다. 재고를 넘기면 발급 없이 빈 리스트.

    재고가 있는 쿠폰이면 coupon은 lock_coupon으로 가져온 행이어야 한다 — 그래야 세기와 발급
    사이에 다른 발급이 끼지 못한다. READ COMMITTED에서 잠금 대기가 풀린 뒤의 count는 먼저
    commit된 발급을 본다. stock이 None이면 그냥 발급한다.
    """
    if coupon.stock is not None and issued_count(db, coupon.id) + len(user_ids) > coupon.stock:
        return []
    codes = _fresh_codes(db, len(user_ids))
    issued = [
        UserCoupon(coupon_id=coupon.id, user_id=uid, grant_key=grant_key, run_id=run_id, code=code)
        for uid, code in zip(user_ids, codes)
    ]
    db.add_all(issued)
    return issued


def on_course_completed(
    db: Session, user_id: str, course_id: uuid.UUID, run_id: uuid.UUID | None = None
) -> None:
    """완주 인증이 통과했을 때. 코스완료 쿠폰이 켜져 있으면 추첨한다."""
    coupon = active_coupon(db, COURSE_COMPLETE)
    if coupon is not None:
        draw(db, coupon, user_id, course_grant_key(course_id), run_id)


def on_bingo_completed(
    db: Session, user_id: str, week_id: uuid.UUID, run_id: uuid.UUID | None
) -> None:
    """러닝위크 빙고판을 다 채웠을 때. 스페셜 쿠폰이 켜져 있으면 추첨한다."""
    coupon = active_coupon(db, BINGO_COMPLETE)
    if coupon is not None:
        draw(db, coupon, user_id, bingo_grant_key(week_id), run_id)


def on_bingo_lines(
    db: Session, user_id: str, week_id: uuid.UUID, lines: int, run_id: uuid.UUID | None
) -> None:
    """빙고 줄 수가 lines일 때. 기준 줄 수 이하인 리워드마다 추첨한다(기준마다 한 번).

    템플릿을 줄 수 오름차순 고정 순서로 돌아 교착이 없다. 꺼져 있거나 기한이 지난 템플릿은
    기록 없이 건너뛴다(나중에 켜면 다음 완주 때 추첨).
    """
    lines_expr = Coupon.trigger_params["lines"].as_integer()
    coupons = db.execute(
        select(Coupon)
        .where(Coupon.trigger_type == BINGO_LINES, lines_expr <= lines)
        .order_by(lines_expr)
    ).scalars()
    now = datetime.now(timezone.utc)
    for coupon in coupons:
        if _usable(coupon, now):
            draw(db, coupon, user_id, bingo_lines_grant_key(week_id, lines_of(coupon)), run_id)


def draw(
    db: Session, coupon: Coupon, user_id: str, grant_key: str, run_id: uuid.UUID | None
) -> UserCoupon | None:
    """이 조건(grant_key)으로 한 번 추첨하고 당첨이면 발급한다. 이미 뽑았거나 받았으면 아무것도 안 한다.

    순서: (재고 있으면 템플릿 잠금) → 추첨 기록·기존 발급 확인 → 재고 확인(소진이면 sold_out)
    → 추첨 → 당첨이면 발급 + won, 아니면 lost. 잠금 뒤에 확인하므로 같은 사람의 동시 요청도,
    다른 사람과의 재고 경쟁도 직렬화된다. 재고 없는 쿠폰은 잠그지 않고, 동시 중복은 추첨
    기록의 유일 제약이 commit 시점에 막는다.
    """
    if coupon.stock is not None:
        coupon = lock_coupon(db, coupon.id)
        if coupon is None:
            return None
    if _already_drawn(db, coupon.id, user_id, grant_key) or _already_granted(
        db, coupon.id, user_id, grant_key
    ):
        return None
    if coupon.stock is not None and issued_count(db, coupon.id) >= coupon.stock:
        _record(db, coupon, user_id, grant_key, DRAW_SOLD_OUT, None, run_id)
        return None
    if not _roll(coupon):
        _record(db, coupon, user_id, grant_key, DRAW_LOST, None, run_id)
        return None
    issued = issue_with_stock(db, coupon, [user_id], grant_key=grant_key, run_id=run_id)
    if not issued:
        _record(db, coupon, user_id, grant_key, DRAW_SOLD_OUT, None, run_id)
        return None
    db.flush()
    _record(db, coupon, user_id, grant_key, DRAW_WON, issued[0].id, run_id)
    return issued[0]


def _roll(coupon: Coupon) -> bool:
    percent = max(0, min(int(coupon.win_rate_percent), 100))
    return _rng.randrange(100) < percent


def _already_drawn(db: Session, coupon_id: uuid.UUID, user_id: str, grant_key: str) -> bool:
    return (
        db.execute(
            select(CouponDraw.id).where(
                CouponDraw.coupon_id == coupon_id,
                CouponDraw.user_id == user_id,
                CouponDraw.grant_key == grant_key,
            )
        ).scalar_one_or_none()
        is not None
    )


def _already_granted(db: Session, coupon_id: uuid.UUID, user_id: str, grant_key: str) -> bool:
    """추첨 기록 도입 전에 확정 지급된 쿠폰(기록 없음)도 다시 뽑지 않는다."""
    return (
        db.execute(
            select(UserCoupon.id).where(
                UserCoupon.coupon_id == coupon_id,
                UserCoupon.user_id == user_id,
                UserCoupon.grant_key == grant_key,
            )
        ).scalar_one_or_none()
        is not None
    )


def _record(
    db: Session,
    coupon: Coupon,
    user_id: str,
    grant_key: str,
    result: str,
    user_coupon_id: uuid.UUID | None,
    run_id: uuid.UUID | None,
) -> None:
    db.add(
        CouponDraw(
            coupon_id=coupon.id,
            user_id=user_id,
            grant_key=grant_key,
            result=result,
            user_coupon_id=user_coupon_id,
            run_id=run_id,
        )
    )
