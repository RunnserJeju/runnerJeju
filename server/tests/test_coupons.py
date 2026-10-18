"""쿠폰 운영자/앱 라우터 + 자동 지급 규칙 테스트.

DB 없이 Session 최소 인터페이스만 흉내낸다(다른 테스트와 같은 방침). SQL 자체는
검증하지 않으므로 집계 매핑·발급 필터·유효상태 계산·사용 상태전이(중복/만료/남의것/
업체 제한)·코스완료 지급의 멱등을 본다.
"""

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import coupon_rules
from app.admin import coupons as admin_coupons
from app.models import Coupon, Partner, UserCoupon
from app.routers import coupons as app_coupons
from app.schemas import CouponUseRequest, IssueRequest

NOW = datetime(2026, 9, 6, 12, 0, tzinfo=timezone.utc)
PAST = datetime(2020, 1, 1, tzinfo=timezone.utc)
FUTURE = datetime(2099, 1, 1, tzinfo=timezone.utc)


class _Result:
    """execute 결과 흉내. rows 하나로 .scalars()/.all()/.first()/.scalar_one_or_none()을 다 받는다."""

    def __init__(self, rows, rowcount=1):
        self._rows = rows
        self.rowcount = rowcount

    def scalars(self):
        return self._rows

    def all(self):
        return self._rows

    def first(self):
        return self._rows[0] if self._rows else None

    def scalar_one_or_none(self):
        return self._rows[0] if self._rows else None


class SeqFake:
    """execute를 호출 순서대로 canned 결과로 답한다. get은 모델별 고정 객체."""

    def __init__(self, results, gets=None):
        self._results = list(results)
        self._gets = gets or {}
        self.added = []
        self.committed = False

    def execute(self, _stmt):
        return self._results.pop(0)

    def get(self, model, _key):
        return self._gets.get(model)

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self.committed = True

    def refresh(self, _obj):
        pass


def _coupon(**over) -> Coupon:
    fields = dict(id=uuid.uuid4(), name="가을쿠폰", benefit="아메리카노 1잔",
                  description=None, valid_until=None, trigger_type="manual",
                  is_active=True)
    fields.update(over)
    return Coupon(**fields)


def _uc(**over) -> UserCoupon:
    fields = dict(id=uuid.uuid4(), coupon_id=uuid.uuid4(), user_id="u1",
                  issued_at=NOW, used_at=None, expired_at=None, used_partner_id=None,
                  grant_key=None)
    fields.update(over)
    return UserCoupon(**fields)


def _partner(**over) -> Partner:
    fields = dict(id=uuid.uuid4(), name="카페", lat=33.5, lng=126.5, detail={})
    fields.update(over)
    return Partner(**fields)


# --- 유효상태 계산 --------------------------------------------------------


class TestEffectiveStatus:
    def test_used(self):
        assert app_coupons._effective_status(NOW, None, NOW) == "used"

    def test_expired(self):
        assert app_coupons._effective_status(None, PAST, NOW) == "expired"

    def test_available_no_expiry(self):
        assert app_coupons._effective_status(None, None, NOW) == "available"

    def test_available_before_expiry(self):
        assert app_coupons._effective_status(None, FUTURE, NOW) == "available"

    def test_used_wins_over_expired(self):
        # 사용완료면 만료보다 우선(이미 썼으니).
        assert app_coupons._effective_status(NOW, PAST, NOW) == "used"

    def test_stored_expired_at(self):
        assert app_coupons._effective_status(None, None, NOW, PAST) == "expired"


# --- 운영자: 목록 ---------------------------------------------------------


class TestListCoupons:
    def test_list_with_batch_counts(self):
        a, b = _coupon(name="A"), _coupon(name="B", trigger_type="course_complete")
        db = SeqFake([_Result([a, b]), _Result([(a.id, 5), (b.id, 2)]), _Result([(a.id, 1)])])

        result = admin_coupons.list_coupons(db)

        by = {r["name"]: r for r in result}
        assert by["A"]["issued_count"] == 5 and by["A"]["used_count"] == 1
        assert by["B"]["issued_count"] == 2 and by["B"]["used_count"] == 0
        assert by["B"]["trigger_type"] == "course_complete"
        assert by["A"]["partner_ids"] == []


class TestIssuedUsedCounts:
    def test_maps_two_queries(self):
        a, b = uuid.uuid4(), uuid.uuid4()
        db = SeqFake([_Result([(a, 5), (b, 2)]), _Result([(a, 1)])])
        issued, used = admin_coupons._issued_used_counts(db, [a, b])
        assert issued == {a: 5, b: 2}
        assert used == {a: 1}

    def test_empty_ids_skip_query(self):
        class Boom:
            def execute(self, _stmt):
                raise AssertionError("빈 id에는 쿼리하면 안 된다")

        assert admin_coupons._issued_used_counts(Boom(), []) == ({}, {})


# --- 운영자: 지급 ---------------------------------------------------------


class TestIssueCoupon:
    def test_issues_only_to_existing_users(self):
        coupon = _coupon()
        u1, u2, ghost = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        db = SeqFake([_Result([u1, u2])], gets={Coupon: coupon})  # ghost는 실존 안 함

        result = admin_coupons.issue_coupon(
            coupon.id, IssueRequest(user_ids=[u1, u2, ghost]), db
        )

        assert result == {"issued": 2}
        assert {uc.user_id for uc in db.added} == {str(u1), str(u2)}
        assert db.committed is True

    def test_404_when_coupon_missing(self):
        db = SeqFake([])
        with pytest.raises(HTTPException) as exc:
            admin_coupons.issue_coupon(
                uuid.uuid4(), IssueRequest(user_ids=[uuid.uuid4()]), db
            )
        assert exc.value.status_code == 404

    def test_request_requires_at_least_one_user(self):
        with pytest.raises(ValidationError):
            IssueRequest(user_ids=[])


# --- 앱: 내 쿠폰 + 사용 ---------------------------------------------------


class TestMyCoupons:
    def test_maps_rows_partner_restriction_and_status(self):
        free, limited = _coupon(name="아무데나"), _coupon(name="한 곳만")
        partner = uuid.uuid4()
        rows = [(_uc(coupon_id=free.id), free), (_uc(coupon_id=limited.id), limited)]
        # 첫 execute는 만료 표시 UPDATE.
        db = SeqFake([_Result([]), _Result(rows), _Result([(limited.id, partner)])])

        result = app_coupons.my_coupons(db=db, user_id="u1")

        by = {r["name"]: r for r in result}
        assert by["아무데나"]["partner_ids"] is None
        assert by["한 곳만"]["partner_ids"] == [partner]
        assert by["아무데나"]["status"] == "available"

    def test_used_partner_name_attached(self):
        coupon = _coupon()
        partner = _partner(name="바다카페")
        rows = [(_uc(coupon_id=coupon.id, used_at=NOW, used_partner_id=partner.id), coupon)]
        db = SeqFake(
            [_Result([]), _Result(rows), _Result([]), _Result([(partner.id, "바다카페")])]
        )

        result = app_coupons.my_coupons(db=db, user_id="u1")

        assert result[0]["status"] == "used"
        assert result[0]["used_partner_name"] == "바다카페"


def _use_db(uc, coupon, partner, *, allowed=(), rowcount=1):
    """use_coupon이 부르는 순서: 내 쿠폰 조회 → get(Partner) → 업체 제한 → 조건부 UPDATE."""
    row = [(uc, coupon)] if uc is not None else []
    links = [(coupon.id, pid) for pid in allowed] if coupon is not None else []
    return SeqFake(
        [_Result(row), _Result(links), _Result([], rowcount=rowcount)],
        gets={Partner: partner},
    )


class TestUseCoupon:
    def test_success_records_partner(self):
        coupon, partner = _coupon(), _partner(name="바다카페")
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = _use_db(uc, coupon, partner)

        result = app_coupons.use_coupon(
            uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
        )

        assert result["status"] == "used"
        assert result["used_at"] is not None
        assert result["used_partner_name"] == "바다카페"
        assert db.committed is True

    def test_allowed_partner_passes(self):
        coupon, partner = _coupon(), _partner()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = _use_db(uc, coupon, partner, allowed=[partner.id])

        result = app_coupons.use_coupon(
            uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
        )
        assert result["status"] == "used"
        assert result["partner_ids"] == [partner.id]

    def test_400_when_partner_not_allowed(self):
        coupon, partner = _coupon(), _partner()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = _use_db(uc, coupon, partner, allowed=[uuid.uuid4()])

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
            )
        assert exc.value.status_code == 400
        assert db.committed is False

    def test_404_when_partner_missing(self):
        coupon = _coupon()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = _use_db(uc, coupon, None)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=uuid.uuid4()), db=db, user_id="u1"
            )
        assert exc.value.status_code == 404

    def test_404_when_not_mine(self):
        # 소유 조건은 쿼리 WHERE에 있다 — 남의 것이면 행이 안 나온다.
        db = _use_db(None, None, _partner())

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uuid.uuid4(), CouponUseRequest(partner_id=uuid.uuid4()), db=db, user_id="u1"
            )
        assert exc.value.status_code == 404

    def test_409_when_already_used(self):
        coupon, partner = _coupon(), _partner()
        uc = _uc(user_id="u1", used_at=NOW, coupon_id=coupon.id)
        db = _use_db(uc, coupon, partner)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
            )
        assert exc.value.status_code == 409

    def test_410_when_expired_and_marks_expired(self):
        # 유효기간이 지났으면 expired_at을 남기고(UPDATE + commit) 410.
        coupon, partner = _coupon(valid_until=PAST), _partner()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = SeqFake([_Result([(uc, coupon)]), _Result([], rowcount=1)], gets={Partner: partner})

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
            )
        assert exc.value.status_code == 410
        assert db.committed is True

    def test_410_when_already_marked_expired(self):
        coupon, partner = _coupon(), _partner()
        uc = _uc(user_id="u1", coupon_id=coupon.id, expired_at=PAST)
        db = SeqFake([_Result([(uc, coupon)])], gets={Partner: partner})

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
            )
        assert exc.value.status_code == 410
        assert db.committed is False

    def test_409_when_concurrent_race_loses(self):
        # 조건부 UPDATE 영향 행 0 → 동시에 다른 요청이 먼저 사용 처리 → 409.
        coupon, partner = _coupon(), _partner()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = _use_db(uc, coupon, partner, rowcount=0)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(
                uc.id, CouponUseRequest(partner_id=partner.id), db=db, user_id="u1"
            )
        assert exc.value.status_code == 409


# --- 자동 지급: 코스 완주 -------------------------------------------------


class TestCourseCompleteGrant:
    def test_grants_one_with_course_key(self):
        coupon = _coupon(trigger_type="course_complete")
        course_id = uuid.uuid4()
        db = SeqFake([_Result([coupon]), _Result([])])  # 켜진 쿠폰 있음, 기존 발급 없음

        coupon_rules.on_course_completed(db, "u1", course_id)

        assert len(db.added) == 1
        assert db.added[0].coupon_id == coupon.id
        assert db.added[0].grant_key == f"course:{course_id}"

    def test_skips_when_already_granted(self):
        coupon = _coupon(trigger_type="course_complete")
        db = SeqFake([_Result([coupon]), _Result([uuid.uuid4()])])

        coupon_rules.on_course_completed(db, "u1", uuid.uuid4())

        assert db.added == []

    def test_skips_when_no_active_coupon(self):
        db = SeqFake([_Result([])])

        coupon_rules.on_course_completed(db, "u1", uuid.uuid4())

        assert db.added == []
