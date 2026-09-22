"""지표(metrics) 라우터·등록부 테스트 — 등록 규칙, 기간 기본값, 결과 후처리, 원본 로그 커서.

DB 없이 Session 최소 인터페이스만 흉내낸다(다른 테스트와 같은 방침). SQL 자체는
검증하지 않는다 — 실제 쿼리는 로컬 스택에서 실 DB로 확인한다.
"""

import uuid
from datetime import date, datetime, timezone

import pytest
from fastapi import HTTPException

from app import user_log
from app.admin import user_logs as user_logs_router
from app.admin.metrics import router as metrics_router
from app.admin.metrics import sources
from app.admin.metrics.registry import COURSE_LOGS, GROUPS, METRICS, Metric


class TestRegistry:
    def test_every_log_name_is_a_metric(self):
        for name in user_log.LOG_NAMES:
            assert name in METRICS

    def test_course_logs_support_course_group_by(self):
        for name in COURSE_LOGS:
            assert name in user_log.LOG_NAMES, f"{name}은 LOG_NAMES에 없다"
            assert "course" in METRICS[name].group_bys
        assert "course" not in METRICS["banner_click"].group_bys

    def test_every_metric_group_is_a_known_tab(self):
        assert all(m.group in GROUPS for m in METRICS.values())

    def test_group_assignments(self):
        assert METRICS["completions"].group == "러닝"
        assert METRICS["course_detail_open_unique"].group == "코스"
        assert METRICS["signups"].group == "계정"
        assert METRICS["coupons_issued"].group == "스탬프·쿠폰"
        assert METRICS["app_open"].group == "기타"

    def test_explicit_metrics_present(self):
        for name in ("course_detail_open_unique", "signups", "incomplete_runs", "coupons_used"):
            assert name in METRICS


class TestResolvePeriod:
    def test_day_defaults_to_last_30_days(self):
        start, end = metrics_router.resolve_period(None, date(2026, 9, 30), "day")
        assert (start, end) == (date(2026, 9, 1), date(2026, 9, 30))

    def test_none_defaults_to_all_time(self):
        start, end = metrics_router.resolve_period(None, date(2026, 9, 30), "none")
        assert start is None and end == date(2026, 9, 30)

    def test_rejects_inverted_range(self):
        with pytest.raises(HTTPException) as exc:
            metrics_router.resolve_period(date(2026, 9, 5), date(2026, 9, 1), "day")
        assert exc.value.status_code == 422


class TestGetMetric:
    def test_unknown_name_404(self):
        with pytest.raises(HTTPException) as exc:
            metrics_router.get_metric("nope", "none")
        assert exc.value.status_code == 404

    def test_unsupported_group_by_422(self):
        with pytest.raises(HTTPException) as exc:
            metrics_router.get_metric("banner_click", "course")
        assert exc.value.status_code == 422


class TestEvaluate:
    def test_day_fills_missing_dates_with_zero(self):
        metric = Metric("m", "m", lambda db, s, e, g: [(date(2026, 9, 2), 3)], ("day",))
        points = metrics_router.evaluate(None, metric, date(2026, 9, 1), date(2026, 9, 3), "day")
        assert [(p["key"], p["count"]) for p in points] == [
            ("2026-09-01", 0), ("2026-09-02", 3), ("2026-09-03", 0),
        ]

    def test_none_returns_single_total(self):
        metric = Metric("m", "m", lambda db, s, e, g: [(None, 7)], ("none",))
        assert metrics_router.evaluate(None, metric, None, date(2026, 9, 3), "none") == [
            {"key": None, "name": None, "count": 7}
        ]

    def test_none_with_no_rows_is_zero(self):
        metric = Metric("m", "m", lambda db, s, e, g: [], ("none",))
        assert metrics_router.evaluate(None, metric, None, date(2026, 9, 3), "none")[0]["count"] == 0

    def test_course_attaches_names_and_sorts_desc(self):
        a, b = uuid.uuid4(), uuid.uuid4()

        class Fake:
            def execute(self, _stmt):
                class R:
                    def all(self):
                        return [(a, "A코스"), (b, "B코스")]
                return R()

        # 로그는 텍스트 키, 테이블은 UUID 키로 올 수 있다 — 둘 다 같은 코스로 합쳐진다.
        metric = Metric("m", "m", lambda db, s, e, g: [(str(a), 2), (b, 5), (a, 1), ("bad", 9)], ("course",))
        points = metrics_router.evaluate(Fake(), metric, None, date(2026, 9, 3), "course")
        assert [(p["name"], p["count"]) for p in points] == [("B코스", 5), ("A코스", 3)]


class TestDifference:
    def test_subtracts_per_key_and_clamps_at_zero(self):
        a = lambda db, s, e, g: [("x", 5), ("y", 2)]
        b = lambda db, s, e, g: [("x", 1), ("y", 4), ("z", 3)]
        result = dict(sources.difference(a, b)(None, None, None, "course"))
        assert result == {"x": 4, "y": 0, "z": 0}


class TestUserLogCursor:
    def test_round_trip(self):
        ts = datetime(2026, 9, 20, 3, 4, 5, tzinfo=timezone.utc)
        log_id = uuid.uuid4()
        cursor = user_logs_router.encode_cursor(ts, log_id)
        assert user_logs_router.decode_cursor(cursor) == (ts, log_id)

    def test_garbage_422(self):
        with pytest.raises(HTTPException) as exc:
            user_logs_router.decode_cursor("not-a-cursor")
        assert exc.value.status_code == 422
