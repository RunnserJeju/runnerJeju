"""이용 통계 운영자 라우터 테스트 — 배치 집계·정렬·overview 매핑.

DB 없이 Session 최소 인터페이스만 흉내낸다(test_users.py와 같은 방침). SQL 자체
(조인·group_by)는 fake로 검증하지 않으므로 배치 헬퍼 매핑·정렬·응답 shape를 본다.
"""

import uuid

from app.admin import stats as stats_router
from app.models import Course


class _AllResult:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class TestBatchCounts:
    def test_favorite_counts_maps_rows(self):
        a, b = uuid.uuid4(), uuid.uuid4()

        class Fake:
            def execute(self, _stmt):
                return _AllResult([(a, 5), (b, 2)])

        assert stats_router._favorite_counts(Fake(), [a, b]) == {a: 5, b: 2}

    def test_runner_counts_maps_rows(self):
        a, b = uuid.uuid4(), uuid.uuid4()

        class Fake:
            def execute(self, _stmt):
                return _AllResult([(a, 3), (b, 9)])

        assert stats_router._runner_counts(Fake(), [a, b]) == {a: 3, b: 9}

    def test_view_counts_maps_rows(self):
        a, b = uuid.uuid4(), uuid.uuid4()

        class Fake:
            def execute(self, _stmt):
                return _AllResult([(a, 12), (b, 3)])

        assert stats_router._view_counts(Fake(), [a, b]) == {a: 12, b: 3}

    def test_empty_ids_skip_query(self):
        class Boom:
            def execute(self, _stmt):
                raise AssertionError("빈 id에는 쿼리하면 안 된다")

        assert stats_router._favorite_counts(Boom(), []) == {}
        assert stats_router._runner_counts(Boom(), []) == {}
        assert stats_router._view_counts(Boom(), []) == {}


class OverviewFakeSession:
    """scalar를 호출 순서대로 소비한다 — overview의 필드 매핑 순서를 검증한다."""

    def __init__(self, values):
        self._values = list(values)

    def scalar(self, _stmt):
        return self._values.pop(0)


class TestOverview:
    def test_maps_fields_in_order(self):
        # 순서: registered, active, runs, completions, favorites, views
        db = OverviewFakeSession([11, 4, 30, 8, 15, 42])

        result = stats_router.stats_overview(db=db)

        assert result == {
            "registered_users": 11,
            "active_users": 4,
            "total_runs": 30,
            "total_completions": 8,
            "total_favorites": 15,
            "total_views": 42,
        }


class CoursesFakeSession:
    def __init__(self, courses):
        self._courses = courses

    def execute(self, _stmt):
        # stats_courses는 select(id, name, address).all()로 읽는다. Row 대신 Course를
        # 그대로 돌려줘도 .id/.name/.address 접근이 같아 테스트가 성립한다.
        return _AllResult(self._courses)


def _course(name: str) -> Course:
    return Course(id=uuid.uuid4(), name=name, address="제주")


class TestStatsCourses:
    def _patch_counts(self, monkeypatch, *, completions=None, favorites=None, runners=None, views=None):
        monkeypatch.setattr(stats_router, "_completed_counts", lambda db, ids: completions or {})
        monkeypatch.setattr(stats_router, "_favorite_counts", lambda db, ids: favorites or {})
        monkeypatch.setattr(stats_router, "_runner_counts", lambda db, ids: runners or {})
        monkeypatch.setattr(stats_router, "_view_counts", lambda db, ids: views or {})

    def test_sorts_by_completions_desc(self, monkeypatch):
        a, b, c = _course("A"), _course("B"), _course("C")
        self._patch_counts(monkeypatch, completions={a.id: 1, b.id: 9, c.id: 5})
        db = CoursesFakeSession([a, b, c])

        result = stats_router.stats_courses(sort="completions", db=db)

        assert [r["name"] for r in result] == ["B", "C", "A"]
        assert result[0]["completed_count"] == 9

    def test_sorts_by_favorites(self, monkeypatch):
        a, b = _course("A"), _course("B")
        self._patch_counts(monkeypatch, favorites={a.id: 7, b.id: 2})
        db = CoursesFakeSession([a, b])

        result = stats_router.stats_courses(sort="favorites", db=db)

        assert [r["name"] for r in result] == ["A", "B"]

    def test_sorts_by_runners(self, monkeypatch):
        a, b = _course("A"), _course("B")
        self._patch_counts(monkeypatch, runners={a.id: 2, b.id: 8})
        db = CoursesFakeSession([a, b])

        result = stats_router.stats_courses(sort="runners", db=db)

        assert [r["name"] for r in result] == ["B", "A"]

    def test_sorts_by_views(self, monkeypatch):
        a, b = _course("A"), _course("B")
        self._patch_counts(monkeypatch, views={a.id: 3, b.id: 20})
        db = CoursesFakeSession([a, b])

        result = stats_router.stats_courses(sort="views", db=db)

        assert [r["name"] for r in result] == ["B", "A"]
        assert result[0]["view_count"] == 20

    def test_missing_metrics_default_to_zero(self, monkeypatch):
        a = _course("A")
        self._patch_counts(monkeypatch)  # 전부 빈 dict
        db = CoursesFakeSession([a])

        result = stats_router.stats_courses(sort="completions", db=db)

        assert result[0]["completed_count"] == 0
        assert result[0]["favorite_count"] == 0
        assert result[0]["runner_count"] == 0
        assert result[0]["view_count"] == 0

    def test_ties_broken_by_name_asc(self, monkeypatch):
        b, a = _course("B"), _course("A")
        # 완주 수 동점 → 이름 오름차순(A, B)
        self._patch_counts(monkeypatch, completions={a.id: 3, b.id: 3})
        db = CoursesFakeSession([b, a])

        result = stats_router.stats_courses(sort="completions", db=db)

        assert [r["name"] for r in result] == ["A", "B"]
