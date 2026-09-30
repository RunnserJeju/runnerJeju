"""앱용 GET /partners 테스트. DB 없이 라우터 함수를 직접 부른다(test_courses.py와 같은 방침).

라우터는 execute를 두 번 부른다 — 업체 목록, 그다음 (업체 id, 코스 id, 코스 이름) 연결.
"""

import uuid

from app.models import Partner
from app.routers import partners as partners_router


class _Result:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows

    def all(self):
        return self._rows


class FakeSession:
    def __init__(self, partners, links):
        self._results = [_Result(partners), _Result(links)]
        self.statements = []

    def execute(self, stmt):
        self.statements.append(stmt)
        return self._results.pop(0)


def _partner(name: str, **overrides) -> Partner:
    fields = dict(
        id=uuid.uuid4(),
        name=name,
        address=None,
        lat=33.5,
        lng=126.5,
        comment=None,
        instagram=None,
        benefit=None,
        detail={"category": "cafe"},
    )
    fields.update(overrides)
    return Partner(**fields)


def test_attaches_linked_courses_per_partner():
    cafe, diner = _partner("카페"), _partner("식당")
    course_a, course_b = uuid.uuid4(), uuid.uuid4()
    db = FakeSession(
        [cafe, diner],
        [(cafe.id, course_a, "A 코스"), (cafe.id, course_b, "B 코스")],
    )

    result = partners_router.list_partners(db, "user-1", False)

    assert [p.name for p in result] == ["카페", "식당"]
    assert [c.name for c in result[0].courses] == ["A 코스", "B 코스"]
    # 연결이 없는 업체도 빠지지 않는다 — 협력업체 모드는 코스와 무관하게 전부 찍는다.
    assert result[1].courses == []
    assert result[0].detail == {"category": "cafe"}


def test_hides_non_public_courses_for_regular_users():
    db = FakeSession([], [])

    partners_router.list_partners(db, "user-1", False)

    # 두 번째 쿼리(연결 코스)에 코스 목록과 같은 공개 필터가 걸린다.
    assert "courses.visibility" in str(db.statements[1])


def test_admin_sees_all_linked_courses():
    db = FakeSession([], [])

    partners_router.list_partners(db, "admin-1", True)

    assert "courses.visibility" not in str(db.statements[1])
