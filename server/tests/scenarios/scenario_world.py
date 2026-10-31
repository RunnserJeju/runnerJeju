"""시나리오의 시작 상황을 DB에 만들고, 사용자가 받은 것을 DB에서 읽는다."""

import uuid
from collections import Counter
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import bingo, coupon_rules
from app.models import (
    Coupon,
    CouponDraw,
    Course,
    Run,
    RunningWeek,
    RunningWeekParticipation,
    Stamp,
    StampDefinition,
    UserCoupon,
)
from app.routers import verifications
from app.schemas import VerificationCreate
from scenario_model import (
    BASIC,
    GEN,
    R1,
    R3,
    R5,
    RW,
    SPECIAL,
    Complete,
    Setup,
    line_stamp,
    lost,
    sold_out,
)

COURSE_COUNT = 25
# 코스 하나는 위도 방향 약 285m 직선. 러닝이 같은 점을 지나면 검증이 matched로 나온다.
_COURSE_POINTS = [{"lat": 33.45 + i * 0.000135, "lng": 126.5} for i in range(20)]
_FAR_POINTS = [{"lat": p["lat"] + 0.1, "lng": p["lng"]} for p in _COURSE_POINTS]

_COUPON_BY_KEY = {
    "general": ("course_complete", None),
    "special": ("bingo_complete", None),
    "r1": ("bingo_lines", 1),
    "r3": ("bingo_lines", 3),
    "r5": ("bingo_lines", 5),
}
_LABEL_BY_KEY = {"general": GEN, "special": SPECIAL, "r1": R1, "r3": R3, "r5": R5}


class World:
    """한 시나리오를 위해 만든 데이터. 사건을 실행하는 메서드도 여기 있다."""

    def __init__(self, db: Session):
        self.db = db
        self.week_id: uuid.UUID
        self.course_ids: list[uuid.UUID] = []
        self.rw_def_ids: list[uuid.UUID] = []
        self.coupon_ids: dict[str, uuid.UUID] = {}

    # ---- 시작 상황 만들기 ----

    @classmethod
    def build(cls, db: Session, setup: Setup) -> "World":
        world = cls(db)
        world._build_week(setup)
        world._build_courses(setup)
        world._build_coupons(setup)
        if setup.participates:
            world.join("me")
        db.commit()
        return world

    def _build_week(self, setup: Setup) -> None:
        now = datetime.now(timezone.utc)
        starts, ends = {
            "open": (now - timedelta(days=1), now + timedelta(days=7)),
            "inactive": (now - timedelta(days=1), now + timedelta(days=7)),
            "before": (now + timedelta(days=1), now + timedelta(days=8)),
            "after": (now - timedelta(days=8), now - timedelta(days=1)),
        }[setup.week]
        week = RunningWeek(
            id=uuid.uuid4(),
            round=1,
            title="테스트 러닝위크",
            is_active=setup.week != "inactive",
            visibility="public",
            starts_at=starts,
            ends_at=ends,
            bingo_stamp_ids=[],
        )
        self.db.add(week)
        self.db.flush()
        self.week_id = week.id

    def _build_courses(self, setup: Setup) -> None:
        for index in range(COURSE_COUNT):
            course = Course(
                id=uuid.uuid4(),
                name=f"코스 {index + 1}",
                category="road",
                visibility="public",
                distance_km=0.3,
                difficulty=1,
                address="제주",
                path=_COURSE_POINTS,
            )
            self.db.add(course)
            self.db.flush()
            self.course_ids.append(course.id)
            self.db.add(
                StampDefinition(
                    id=uuid.uuid4(),
                    name=f"코스 {index + 1} 완주",
                    condition_type="course_complete",
                    condition_params={"course_id": str(course.id)},
                    is_active=True,
                )
            )
            rw = StampDefinition(
                id=uuid.uuid4(),
                name=f"러닝위크 코스 {index + 1}",
                condition_type="running_week_course",
                condition_params={
                    "running_week_id": str(self.week_id),
                    "course_id": str(course.id),
                },
                is_active=True,
            )
            self.db.add(rw)
            self.db.flush()
            self.rw_def_ids.append(rw.id)

        for lines in setup.line_stamps:
            self.db.add(
                StampDefinition(
                    id=uuid.uuid4(),
                    name=f"빙고 {lines}줄",
                    condition_type="bingo_lines",
                    condition_params={"running_week_id": str(self.week_id), "lines": lines},
                    is_active=True,
                )
            )

        if setup.bingo:
            week = self.db.get(RunningWeek, self.week_id)
            week.bingo_stamp_ids = [str(i) for i in self.rw_def_ids]

    def _build_coupons(self, setup: Setup) -> None:
        """마이그레이션이 심은 쿠폰 행을 시나리오 설정으로 덮어쓴다. 적지 않은 쿠폰은 비활성화한다."""
        rows = list(self.db.execute(select(Coupon)).scalars())
        for key, (trigger_type, lines) in _COUPON_BY_KEY.items():
            coupon = next(
                c
                for c in rows
                if c.trigger_type == trigger_type and coupon_rules.lines_of(c) == lines
            )
            self.coupon_ids[key] = coupon.id
            wanted = setup.coupons.get(key)
            coupon.is_active = wanted is not None
            coupon.valid_until = None
            coupon.win_rate_percent = (wanted or {}).get("win", 100)
            coupon.stock = (wanted or {}).get("stock")

    # ---- 사건 ----

    def join(self, who: str) -> None:
        now = datetime.now(timezone.utc)
        self.db.add(
            RunningWeekParticipation(
                running_week_id=self.week_id,
                user_id=who,
                name="테스터",
                phone="010-0000-0000",
                gender="male",
                age=30,
                residence="jeju",
                agreed_at=now,
                expires_at=now + timedelta(days=365),
            )
        )
        self.db.commit()

    def prefill(self, who: str, cells: list[int]) -> None:
        """칸을 채운다 — 그 칸의 코스를 실제로 완주한다. 그래서 그동안 받을 것도 실제로 받은 상태가 된다."""
        for cell in cells:
            self.complete(Complete(cell, who=who))

    def complete(self, event: Complete) -> None:
        now = datetime.now(timezone.utc)
        run = Run(
            id=uuid.uuid4(),
            user_id=event.who,
            course_id=self.course_ids[event.course],
            started_at=now - timedelta(minutes=30),
            ended_at=now,
            distance_meters=285.0,
            duration_sec=1800,
            path=_COURSE_POINTS if event.matched else _FAR_POINTS,
        )
        self.db.add(run)
        self.db.commit()
        for _ in range(2 if event.twice else 1):
            verifications.request_verification(
                run_id=run.id,
                payload=VerificationCreate(course_id=self.course_ids[event.course]),
                db=self.db,
                user_id=event.who,
            )

    def set_coupon(self, key: str, active, win, stock) -> None:
        coupon = self.db.get(Coupon, self.coupon_ids[key])
        if active is not None:
            coupon.is_active = active
        if win is not None:
            coupon.win_rate_percent = win
        if stock is not None:
            coupon.stock = stock
        self.db.commit()

    def admin_issue(self, key: str, count: int) -> None:
        """운영툴 수동 발급(admin/coupons.issue_coupon)과 같은 잠금·재고 확인을 탄다."""
        coupon = coupon_rules.lock_coupon(self.db, self.coupon_ids[key])
        issued = coupon_rules.issue_with_stock(
            self.db, coupon, [f"ops-{n}" for n in range(count)]
        )
        assert len(issued) == count, "수동 발급이 수량 부족으로 실패했어요"
        self.db.commit()

    # ---- 읽기 ----

    def received(self, who: str) -> Counter:
        """who가 지금까지 받은 것(이름별 개수). 낙첨·소진 기록도 센다."""
        self.db.expire_all()
        got: Counter = Counter()

        stamp_rows = self.db.execute(
            select(StampDefinition.condition_type, StampDefinition.condition_params)
            .join(Stamp, Stamp.stamp_definition_id == StampDefinition.id)
            .where(Stamp.user_id == who)
        ).all()
        for condition_type, params in stamp_rows:
            if condition_type == "course_complete":
                got[BASIC] += 1
            elif condition_type == "running_week_course":
                got[RW] += 1
            elif condition_type == "bingo_lines":
                got[line_stamp(int(params["lines"]))] += 1

        coupon_rows = self.db.execute(
            select(Coupon)
            .join(UserCoupon, UserCoupon.coupon_id == Coupon.id)
            .where(UserCoupon.user_id == who)
        ).scalars()
        for coupon in coupon_rows:
            got[self._label(coupon)] += 1

        draw_rows = self.db.execute(
            select(Coupon, CouponDraw.result)
            .join(CouponDraw, CouponDraw.coupon_id == Coupon.id)
            .where(CouponDraw.user_id == who, CouponDraw.result != coupon_rules.DRAW_WON)
        ).all()
        for coupon, result in draw_rows:
            label = self._label(coupon)
            got[lost(label) if result == coupon_rules.DRAW_LOST else sold_out(label)] += 1
        return got

    def board(self, who: str) -> dict | None:
        """who의 빙고판. 칸별 획득 여부와 완성 줄 수. 배치가 없으면 None."""
        self.db.expire_all()
        week = self.db.get(RunningWeek, self.week_id)
        current = bingo.board(self.db, week, who)
        if current is None:
            return None
        return {
            "cells": [cell["acquired"] for cell in current["cells"]],
            "lines": current["completed_lines"],
        }

    @staticmethod
    def _label(coupon: Coupon) -> str:
        if coupon.trigger_type == "course_complete":
            return GEN
        if coupon.trigger_type == "bingo_complete":
            return SPECIAL
        if coupon.trigger_type == "bingo_lines":
            return f"{coupon_rules.lines_of(coupon)}줄 리워드"
        return "수동 쿠폰"
