"""홈 구성 테스트 — 앱 GET /home/curation, 운영자 GET/PUT /admin/home.

DB 없이 라우터 함수를 직접 부른다(test_partners.py와 같은 방침).
"""

import uuid

import pytest
from fastapi import HTTPException

from app.admin import home as admin_home
from app.models import CourseCuration, PartnerCuration
from app.routers import home


class _Result:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return iter(self._rows)


class FakeSession:
    """execute는 미리 넣어 둔 결과를 순서대로 돌려준다. 결과가 떨어지면 빈 결과."""

    def __init__(self, *results):
        self._results = list(results)
        self.statements = []
        self.added = []
        self.committed = False

    def execute(self, stmt):
        self.statements.append(stmt)
        return _Result(self._results.pop(0) if self._results else [])

    def add_all(self, rows):
        self.added.extend(rows)

    def commit(self):
        self.committed = True


def test_app_curation_returns_ids_in_sort_order():
    c1, c2, p1 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    db = FakeSession([c1, c2], [p1])

    result = home.get_home_curation(db, "user-1")

    assert result.course_ids == [c1, c2]
    assert result.partner_ids == [p1]
    assert "ORDER BY course_curations.sort_order" in str(db.statements[0])
    assert "ORDER BY partner_curations.sort_order" in str(db.statements[1])


def test_replaces_courses_in_given_order():
    a, b = uuid.uuid4(), uuid.uuid4()
    # 첫 execute(존재 확인)가 두 id를 모두 찾는다.
    db = FakeSession([a, b])

    admin_home.set_curation_courses(admin_home.HomeCurationPayload(ids=[b, a]), db)

    # 존재 확인 → 전부 지우기 → 고른 순서대로 다시 넣기.
    assert str(db.statements[1]).startswith("DELETE FROM course_curations")
    assert all(isinstance(row, CourseCuration) for row in db.added)
    assert [(row.course_id, row.sort_order) for row in db.added] == [(b, 0), (a, 1)]
    assert db.committed


def test_empty_list_clears_section():
    db = FakeSession()

    admin_home.set_featured_partners(admin_home.HomeCurationPayload(ids=[]), db)

    # 확인할 id가 없으니 select 없이 지우기만 한다.
    assert len(db.statements) == 1
    assert str(db.statements[0]).startswith("DELETE FROM partner_curations")
    assert db.added == []
    assert db.committed


def test_partner_rows_use_partner_table():
    p = uuid.uuid4()
    db = FakeSession([p])

    admin_home.set_featured_partners(admin_home.HomeCurationPayload(ids=[p]), db)

    assert [type(row) for row in db.added] == [PartnerCuration]
    assert db.added[0].partner_id == p


def test_rejects_unknown_ids():
    known, unknown = uuid.uuid4(), uuid.uuid4()
    db = FakeSession([known])

    with pytest.raises(HTTPException) as exc:
        admin_home.set_featured_partners(
            admin_home.HomeCurationPayload(ids=[known, unknown]), db
        )

    assert exc.value.status_code == 422
    assert str(unknown) in exc.value.detail
    assert not db.committed


def test_rejects_duplicates():
    a = uuid.uuid4()
    db = FakeSession([a])

    with pytest.raises(HTTPException) as exc:
        admin_home.set_curation_courses(admin_home.HomeCurationPayload(ids=[a, a]), db)

    assert exc.value.status_code == 422
    assert not db.committed
