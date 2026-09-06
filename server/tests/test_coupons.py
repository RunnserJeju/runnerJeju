"""쿠폰 운영자/앱 라우터 테스트 — 템플릿 CRUD·지급·발급현황·사용(이용완료).

DB 없이 Session 최소 인터페이스만 흉내낸다(다른 테스트와 같은 방침). SQL 자체는
검증하지 않으므로 집계 매핑·발급 필터·유효상태 계산·사용 상태전이(중복/만료/남의것)를 본다.
"""

import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.admin import coupons as admin_coupons
from app.models import Coupon, UserCoupon
from app.routers import coupons as app_coupons
from app.schemas import CouponCreate, IssueRequest

NOW = datetime(2026, 9, 6, 12, 0, tzinfo=timezone.utc)
PAST = datetime(2020, 1, 1, tzinfo=timezone.utc)
FUTURE = datetime(2099, 1, 1, tzinfo=timezone.utc)


class _Result:
    """.scalars()·.all() 둘 다 같은 rows를 준다."""

    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows

    def all(self):
        return self._rows


def _coupon(**over) -> Coupon:
    fields = dict(id=uuid.uuid4(), name="가을쿠폰", benefit="아메리카노 1잔",
                  description=None, valid_until=None)
    fields.update(over)
    return Coupon(**fields)


def _uc(**over) -> UserCoupon:
    fields = dict(id=uuid.uuid4(), coupon_id=uuid.uuid4(), user_id="u1",
                  issued_at=NOW, used_at=None)
    fields.update(over)
    return UserCoupon(**fields)


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


# --- 운영자: 템플릿 CRUD --------------------------------------------------


class AddFake:
    def __init__(self):
        self.added = []
        self.committed = False

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)

    def commit(self):
        self.committed = True

    def refresh(self, _obj):
        pass


class TestCreateCoupon:
    def test_creates_with_zero_counts(self):
        db = AddFake()
        result = admin_coupons.create_coupon(
            CouponCreate(name="가을쿠폰", benefit="아메리카노 1잔"), db
        )
        assert result["name"] == "가을쿠폰"
        assert result["benefit"] == "아메리카노 1잔"
        assert result["issued_count"] == 0 and result["used_count"] == 0
        assert db.committed is True


class SeqExecFake:
    """execute를 호출 순서대로 canned rows로 답한다."""

    def __init__(self, coupons_or_none, *count_row_lists):
        self._seq = list(count_row_lists)
        self._coupons = coupons_or_none

    def execute(self, _stmt):
        # list_coupons: 첫 execute는 select(Coupon).scalars()
        if self._coupons is not None:
            rows, self._coupons = self._coupons, None
            return _Result(rows)
        return _Result(self._seq.pop(0))


class TestListCoupons:
    def test_list_with_batch_counts(self):
        a, b = _coupon(name="A"), _coupon(name="B")
        db = SeqExecFake([a, b], [(a.id, 5), (b.id, 2)], [(a.id, 1)])

        result = admin_coupons.list_coupons(db)

        by = {r["name"]: r for r in result}
        assert by["A"]["issued_count"] == 5 and by["A"]["used_count"] == 1
        assert by["B"]["issued_count"] == 2 and by["B"]["used_count"] == 0


class TestIssuedUsedCounts:
    def test_maps_two_queries(self):
        a, b = uuid.uuid4(), uuid.uuid4()
        db = SeqExecFake(None, [(a, 5), (b, 2)], [(a, 1)])
        issued, used = admin_coupons._issued_used_counts(db, [a, b])
        assert issued == {a: 5, b: 2}
        assert used == {a: 1}

    def test_empty_ids_skip_query(self):
        class Boom:
            def execute(self, _stmt):
                raise AssertionError("빈 id에는 쿼리하면 안 된다")

        assert admin_coupons._issued_used_counts(Boom(), []) == ({}, {})


class DeleteFake:
    def __init__(self, coupon):
        self._coupon = coupon
        self.deleted = []
        self.committed = False

    def get(self, _model, cid):
        return self._coupon if (self._coupon and self._coupon.id == cid) else None

    def delete(self, obj):
        self.deleted.append(obj)

    def commit(self):
        self.committed = True


class TestDeleteCoupon:
    def test_deletes(self):
        c = _coupon()
        db = DeleteFake(c)
        admin_coupons.delete_coupon(c.id, db)
        assert c in db.deleted and db.committed is True

    def test_404(self):
        with pytest.raises(HTTPException) as exc:
            admin_coupons.delete_coupon(uuid.uuid4(), DeleteFake(None))
        assert exc.value.status_code == 404


# --- 운영자: 지급 ---------------------------------------------------------


class IssueFake:
    def __init__(self, coupon, valid_ids):
        self._coupon = coupon
        self._valid = valid_ids  # 실존(비탈퇴) 회원 UUID 목록
        self.added = []
        self.committed = False

    def get(self, _model, cid):
        return self._coupon if (self._coupon and self._coupon.id == cid) else None

    def execute(self, _stmt):
        return _Result(self._valid)

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self.committed = True


class TestIssueCoupon:
    def test_issues_only_to_existing_users(self):
        coupon = _coupon()
        u1, u2, ghost = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        db = IssueFake(coupon, [u1, u2])  # ghost는 실존 안 함

        result = admin_coupons.issue_coupon(
            coupon.id, IssueRequest(user_ids=[u1, u2, ghost]), db
        )

        assert result == {"issued": 2}
        assert {uc.user_id for uc in db.added} == {str(u1), str(u2)}
        assert db.committed is True

    def test_404_when_coupon_missing(self):
        db = IssueFake(None, [])
        with pytest.raises(HTTPException) as exc:
            admin_coupons.issue_coupon(
                uuid.uuid4(), IssueRequest(user_ids=[uuid.uuid4()]), db
            )
        assert exc.value.status_code == 404

    def test_request_requires_at_least_one_user(self):
        with pytest.raises(ValidationError):
            IssueRequest(user_ids=[])


# --- 앱: 내 쿠폰 + 사용 ---------------------------------------------------


class MyCouponsFake:
    def __init__(self, rows):
        self._rows = rows

    def execute(self, _stmt):
        return _Result(self._rows)


class TestMyCoupons:
    def test_maps_rows_and_status(self):
        row = SimpleNamespace(
            id=uuid.uuid4(), issued_at=NOW, used_at=None, name="가을쿠폰",
            description="설명", benefit="아메리카노 1잔", valid_until=None,
        )
        db = MyCouponsFake([row])

        result = app_coupons.my_coupons(db=db, user_id="u1")

        assert result[0]["name"] == "가을쿠폰"
        assert result[0]["benefit"] == "아메리카노 1잔"
        assert result[0]["status"] == "available"


class _UpdateResult:
    def __init__(self, rowcount):
        self.rowcount = rowcount


class UseFake:
    def __init__(self, uc, coupon, rowcount=1):
        self._uc = uc
        self._coupon = coupon
        self._rowcount = rowcount
        self.committed = False

    def get(self, model, _key):
        if model is UserCoupon:
            return self._uc
        if model is Coupon:
            return self._coupon
        return None

    def execute(self, _stmt):
        return _UpdateResult(self._rowcount)

    def commit(self):
        self.committed = True


class TestUseCoupon:
    def test_success(self):
        coupon = _coupon()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = UseFake(uc, coupon, rowcount=1)

        result = app_coupons.use_coupon(uc.id, db=db, user_id="u1")

        assert result["status"] == "used"
        assert result["used_at"] is not None
        assert result["benefit"] == "아메리카노 1잔"
        assert db.committed is True

    def test_404_when_not_mine(self):
        coupon = _coupon()
        uc = _uc(user_id="u2", coupon_id=coupon.id)
        db = UseFake(uc, coupon)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(uc.id, db=db, user_id="u1")
        assert exc.value.status_code == 404

    def test_409_when_already_used(self):
        coupon = _coupon()
        uc = _uc(user_id="u1", used_at=NOW, coupon_id=coupon.id)
        db = UseFake(uc, coupon)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(uc.id, db=db, user_id="u1")
        assert exc.value.status_code == 409

    def test_409_when_expired(self):
        coupon = _coupon(valid_until=PAST)
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = UseFake(uc, coupon)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(uc.id, db=db, user_id="u1")
        assert exc.value.status_code == 409

    def test_409_when_concurrent_race_loses(self):
        # 조건부 UPDATE 영향 행 0 → 동시에 다른 요청이 먼저 사용 처리 → 409.
        coupon = _coupon()
        uc = _uc(user_id="u1", coupon_id=coupon.id)
        db = UseFake(uc, coupon, rowcount=0)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(uc.id, db=db, user_id="u1")
        assert exc.value.status_code == 409

    def test_404_when_template_deleted_mid_use(self):
        # 사용 직전 운영자가 템플릿을 삭제(cascade)하면 coupon 조회가 None → 404.
        uc = _uc(user_id="u1")
        db = UseFake(uc, None)

        with pytest.raises(HTTPException) as exc:
            app_coupons.use_coupon(uc.id, db=db, user_id="u1")
        assert exc.value.status_code == 404
