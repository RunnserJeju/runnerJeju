"""행동 로그 수신(POST /user-logs) 테스트 — 허용 목록·detail 크기·user_id 채움.

DB 없이 Session 최소 인터페이스만 흉내낸다(다른 테스트와 같은 방침).
"""

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import user_log
from app.routers import user_logs as user_logs_router
from app.schemas import UserLogBatchIn


def _batch(*events):
    return UserLogBatchIn(logs=list(events))


class TestValidateBatch:
    def test_accepts_known_names(self):
        rows = user_logs_router.validate_batch(
            _batch(
                {"log_name": "run_start", "detail": {"course_id": "c1"}, "platform": "ios"},
                {"log_name": "banner_click", "session_id": "s1", "app_version": "1.2.0"},
            )
        )

        assert [r["log_name"] for r in rows] == ["run_start", "banner_click"]
        assert rows[0]["detail"] == {"course_id": "c1"}
        assert rows[0]["platform"] == "ios"
        assert rows[1]["session_id"] == "s1"
        assert rows[1]["app_version"] == "1.2.0"

    def test_rejects_unknown_name(self):
        with pytest.raises(HTTPException) as exc:
            user_logs_router.validate_batch(_batch({"log_name": "made_up"}))

        assert exc.value.status_code == 422
        assert "logs[0]" in exc.value.detail

    def test_rejects_oversized_detail(self):
        big = {"blob": "x" * (user_log.DETAIL_MAX_BYTES + 1)}

        with pytest.raises(HTTPException) as exc:
            user_logs_router.validate_batch(_batch({"log_name": "run_finish", "detail": big}))

        assert exc.value.status_code == 422

    def test_rejects_unknown_platform(self):
        with pytest.raises(ValidationError):
            _batch({"log_name": "app_open", "platform": "web"})

    def test_rejects_empty_batch(self):
        with pytest.raises(ValidationError):
            UserLogBatchIn(logs=[])


class _FakeSession:
    def __init__(self):
        self.rows = None
        self.committed = False

    def execute(self, _stmt, rows=None):
        self.rows = rows

    def commit(self):
        self.committed = True


class TestIngest:
    def test_fills_user_id_on_every_row(self):
        db = _FakeSession()

        user_logs_router.write_user_log(
            _batch({"log_name": "run_start"}, {"log_name": "run_finish"}),
            db=db,
            user_id="u1",
        )

        assert [r["user_id"] for r in db.rows] == ["u1", "u1"]
        assert db.committed is True

    def test_anonymous_when_no_token(self):
        db = _FakeSession()

        user_logs_router.write_user_log(_batch({"log_name": "login_failed"}), db=db, user_id=None)

        assert db.rows[0]["user_id"] is None


class TestLogNames:
    def test_course_detail_open_is_allowed(self):
        # 서버가 직접 쓰는 이름도 목록에 있어야 앱이 같은 이름을 쓸 때 거절되지 않는다.
        assert user_log.COURSE_DETAIL_OPEN in user_log.LOG_NAMES
