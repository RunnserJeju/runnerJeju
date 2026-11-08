"""이어달리기 테스트: 기간 경계(KST 오늘 포함 7일)와 구간 이어 붙이기."""

import uuid
from datetime import datetime, timedelta, timezone

from app.models import Run
from app.routers.courses import KST
from app.run_continuation import (
    append_segment,
    continuable_since,
    has_segment,
    is_continuable,
)
from app.schemas import RunContinue

NOW = datetime(2026, 11, 8, 3, 0, tzinfo=timezone.utc)


def test_today_and_six_days_before():
    now = datetime(2026, 11, 8, 15, 0, tzinfo=KST)
    assert continuable_since(now) == datetime(2026, 11, 2, 0, 0, tzinfo=KST)


def test_uses_kst_date_not_utc_date():
    # UTC로는 11/7 16:00이지만 KST로는 이미 11/8 01:00 — 경계가 하루 밀려 있어야 한다.
    now = datetime(2026, 11, 7, 16, 0, tzinfo=timezone.utc)
    assert continuable_since(now) == datetime(2026, 11, 2, 0, 0, tzinfo=KST)


def test_boundary_moves_at_kst_midnight():
    before = datetime(2026, 11, 8, 23, 59, 59, tzinfo=KST)
    after = before + timedelta(seconds=1)
    assert continuable_since(after) - continuable_since(before) == timedelta(days=1)


def test_judged_by_segment_start_not_upload_time():
    # 11/1에 시작한 기록. 11/7 23:50(KST)에 이어 달리기 시작 → 기간 안.
    run_started = datetime(2026, 11, 1, 9, 0, tzinfo=KST)
    assert is_continuable(run_started, at=datetime(2026, 11, 7, 23, 50, tzinfo=KST))
    # 11/8 00:00부터 시작한 구간은 기간 밖.
    assert not is_continuable(run_started, at=datetime(2026, 11, 8, 0, 0, tzinfo=KST))


def _run() -> Run:
    return Run(
        id=uuid.uuid4(),
        user_id="u1",
        course_id=uuid.uuid4(),
        started_at=datetime(2026, 11, 7, 9, 0, tzinfo=KST),
        ended_at=datetime(2026, 11, 7, 9, 30, tzinfo=KST),
        distance_meters=3000.0,
        duration_sec=1800,
        path=[{"lat": 33.0, "lng": 126.0}, {"lat": 33.001, "lng": 126.0}],
        continuations=[],
    )


def _segment(segment_id: uuid.UUID | None = None) -> RunContinue:
    start = datetime(2026, 11, 8, 7, 0, tzinfo=KST)
    return RunContinue(
        segment_id=segment_id or uuid.uuid4(),
        started_at=start,
        ended_at=start + timedelta(minutes=20),
        distance_meters=2000.0,
        duration_sec=1200,
        path=[
            {"lat": 33.01, "lng": 126.01, "recorded_at": start.isoformat()},
            {"lat": 33.011, "lng": 126.01},
        ],
    )


def test_append_adds_totals_and_extends_end():
    run = _run()
    segment = _segment()

    append_segment(run, segment, now=NOW)

    assert run.distance_meters == 5000.0
    assert run.duration_sec == 3000
    assert run.ended_at == segment.ended_at
    # 시작 시각은 원래 기록 그대로 — 기한이 늘지 않는다.
    assert run.started_at == datetime(2026, 11, 7, 9, 0, tzinfo=KST)
    assert run.updated_at == NOW


def test_append_breaks_path_at_first_new_point():
    run = _run()
    append_segment(run, _segment(), now=NOW)

    assert len(run.path) == 4
    assert "segment_break" not in run.path[1]
    # 원래 기록 끝 → 이어 달린 첫 점 사이는 잇지 않는다.
    assert run.path[2]["segment_break"] is True
    # 기본값 필드는 저장하지 않는다(POST /runs와 같은 규칙).
    assert "segment_break" not in run.path[3]


def test_append_records_segment_for_retry_detection():
    run = _run()
    segment_id = uuid.uuid4()
    assert not has_segment(run, segment_id)

    append_segment(run, _segment(segment_id), now=NOW)

    assert has_segment(run, segment_id)
    assert not has_segment(run, uuid.uuid4())
    assert run.continuations[0]["point_count"] == 2
