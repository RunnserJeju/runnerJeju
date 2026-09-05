"""미션 운영자 라우터 테스트 — CRUD와 값 검증.

DB 없이 Session의 최소 인터페이스만 흉내내는 FakeSession을 쓴다(test_notices.py와
같은 방침). require_admin_session 권한 검사는 라우터 함수를 직접 부르면 우회되므로
test_admin_auth.py에서 따로 검증한다.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.admin import missions as missions_router
from app.models import Mission
from app.schemas import MissionCreate, MissionUpdate

NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)
DAY = timedelta(days=1)


def _mission(**over) -> Mission:
    fields = dict(
        id=uuid.uuid4(),
        title="가을 챌린지",
        body="가을 러닝 챌린지입니다.",
        condition="코스 3개 완주",
        reward="굿즈 증정",
        starts_at=None,
        ends_at=None,
        is_active=True,
        sort_order=0,
    )
    fields.update(over)
    return Mission(**fields)


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class FakeSession:
    def __init__(self, missions: list[Mission] | None = None):
        self._missions = list(missions or [])
        self.added: list[object] = []
        self.deleted: list[object] = []

    def execute(self, _stmt):
        return _FakeResult(list(self._missions))

    def get(self, _model, mission_id):
        return next((m for m in self._missions if m.id == mission_id), None)

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)
        self._missions.append(obj)

    def delete(self, obj):
        self.deleted.append(obj)
        self._missions = [m for m in self._missions if m is not obj]

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


def _payload(**over) -> MissionCreate:
    fields = dict(
        title="가을 챌린지",
        body="설명",
        condition="코스 3개 완주",
        reward="굿즈 증정",
    )
    fields.update(over)
    return MissionCreate(**fields)


class TestCreateMission:
    def test_creates_with_all_fields(self):
        db = FakeSession()
        payload = _payload(starts_at=NOW, ends_at=NOW + DAY, sort_order=2, is_active=False)

        result = missions_router.create_mission(payload, db)

        assert result.title == "가을 챌린지"
        assert result.condition == "코스 3개 완주"
        assert result.reward == "굿즈 증정"
        assert result.starts_at == NOW and result.ends_at == NOW + DAY
        assert result.sort_order == 2 and result.is_active is False
        assert result in db.added

    def test_period_defaults_to_none_and_active(self):
        db = FakeSession()
        result = missions_router.create_mission(_payload(), db)

        assert result.starts_at is None and result.ends_at is None
        assert result.is_active is True and result.sort_order == 0


class TestListAndGet:
    def test_list_returns_all(self):
        m1, m2 = _mission(title="A"), _mission(title="B", is_active=False)
        db = FakeSession([m1, m2])

        result = missions_router.list_missions(db)

        assert {m.title for m in result} == {"A", "B"}

    def test_get_returns_one(self):
        m = _mission()
        db = FakeSession([m])

        assert missions_router.get_mission(m.id, db) is m

    def test_get_404_when_missing(self):
        with pytest.raises(HTTPException) as exc:
            missions_router.get_mission(uuid.uuid4(), FakeSession())
        assert exc.value.status_code == 404


class TestUpdateMission:
    def test_replaces_fields(self):
        m = _mission(title="옛", condition="옛 조건", reward="옛 리워드")
        db = FakeSession([m])
        payload = MissionUpdate(
            title="새",
            body="새 설명",
            condition="거리 50km 달성",
            reward="포인트 500",
            starts_at=NOW,
            ends_at=NOW + DAY,
            is_active=False,
            sort_order=5,
        )

        result = missions_router.update_mission(m.id, payload, db)

        assert m.title == "새" and m.condition == "거리 50km 달성"
        assert m.reward == "포인트 500" and m.sort_order == 5
        assert m.is_active is False and m.ends_at == NOW + DAY
        assert result.title == "새"

    def test_404_when_missing(self):
        with pytest.raises(HTTPException) as exc:
            missions_router.update_mission(uuid.uuid4(), _payload(), FakeSession())
        assert exc.value.status_code == 404


class TestDeleteMission:
    def test_deletes(self):
        m = _mission()
        db = FakeSession([m])

        missions_router.delete_mission(m.id, db)

        assert m in db.deleted

    def test_404_when_missing(self):
        with pytest.raises(HTTPException) as exc:
            missions_router.delete_mission(uuid.uuid4(), FakeSession())
        assert exc.value.status_code == 404


class TestMissionSchema:
    def test_rejects_end_before_start(self):
        with pytest.raises(ValidationError):
            MissionCreate(
                title="t", body="b", condition="c", reward="r",
                starts_at=NOW, ends_at=NOW - DAY,
            )

    def test_rejects_blank_condition(self):
        with pytest.raises(ValidationError):
            MissionCreate(title="t", body="b", condition="", reward="r")

    def test_rejects_blank_reward(self):
        with pytest.raises(ValidationError):
            MissionCreate(title="t", body="b", condition="c", reward="")

    def test_allows_equal_start_end(self):
        MissionCreate(
            title="t", body="b", condition="c", reward="r",
            starts_at=NOW, ends_at=NOW,
        )
