"""이어달리기: 완주하지 못한 코스 러닝에 나중에 달린 구간을 이어 붙인다.

이어 달릴 수 있는 기록은 오늘(KST)을 포함한 최근 7일 안에 시작한 미완주 기록이다.
기준은 기록의 처음 시작 시각(started_at)이라, 여러 번 이어 달려도 기한이 늘지 않는다.
목록(GET /runs/continuable)과 이어 붙이기가 같은 경계를 써야 목록에 보인 기록이
저장 때 거부되지 않는다.

이어 붙일 때는 업로드 시각이 아니라 **이어달리기를 시작한 시각**으로 판정한다
([is_continuable]). 마감 직전에 시작해 자정을 넘겨 끝냈거나, 앱이 죽어 며칠 뒤에
복구 업로드되는 구간이 거부돼 사라지지 않게.
"""

import uuid
from datetime import datetime, time, timedelta

from app.models import Run
from app.routers.courses import KST
from app.schemas import RunContinue

# 오늘을 포함한 날 수. 7이면 오늘과 그 전 6일.
CONTINUABLE_DAYS = 7

# 이 거리 이하인 구간은 붙이지 않는다(m). 앱의 RunRecord.minMeters와 같다.
MIN_SEGMENT_METERS = 10


def continuable_since(now: datetime) -> datetime:
    """이어 달릴 수 있는 기록의 started_at 하한(포함). KST 자정에 하루씩 밀린다."""
    today = now.astimezone(KST).date()
    first_day = today - timedelta(days=CONTINUABLE_DAYS - 1)
    return datetime.combine(first_day, time.min, tzinfo=KST)


def is_continuable(run_started_at: datetime, *, at: datetime) -> bool:
    """[at] 시각에 이 기록이 이어 달릴 수 있는 기간 안이었는지."""
    return run_started_at >= continuable_since(at)


def has_segment(run: Run, segment_id: uuid.UUID) -> bool:
    """이 구간이 이미 붙어 있는지(업로드 재시도)."""
    key = str(segment_id)
    return any(c.get("segment_id") == key for c in run.continuations or [])


def append_segment(run: Run, segment: RunContinue, *, now: datetime) -> None:
    """구간을 기록 뒤에 붙인다. 판정(완주·기간·거리)은 부르는 쪽이 먼저 한다.

    구간의 첫 점은 앱이 뭘 보냈든 끊긴 자리로 표시한다. 원래 기록이 끝난 곳에서
    이어달리기를 시작한 곳까지는 달린 길이 아니라, 거리·검증·지도 모두 그 사이를
    잇지 않아야 한다(일시정지 후 재개와 같은 규칙, verification.to_segments).

    JSONB 컬럼은 제자리 수정을 감지하지 못하므로 새 리스트를 대입한다.
    """
    points = [
        point.model_dump(mode="json", exclude_defaults=True) for point in segment.path
    ]
    if points:
        points[0]["segment_break"] = True

    run.path = [*(run.path or []), *points]
    run.distance_meters += segment.distance_meters
    run.duration_sec += segment.duration_sec
    run.ended_at = max(run.ended_at, segment.ended_at)
    run.continuations = [
        *(run.continuations or []),
        {
            "segment_id": str(segment.segment_id),
            "started_at": segment.started_at.isoformat(),
            "ended_at": segment.ended_at.isoformat(),
            "distance_meters": segment.distance_meters,
            "duration_sec": segment.duration_sec,
            "point_count": len(points),
            "appended_at": now.isoformat(),
        },
    ]
    run.updated_at = now
