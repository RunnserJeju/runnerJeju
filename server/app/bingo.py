"""러닝위크 빙고판 계산과 빙고 보상. 회차·참가 여부 판단은 부르는 쪽(app.running_week)이 한다.

칸이 채워졌는지는 저장하지 않고 발급 기록(stamps)에서 계산한다. 화면 조회와 보상 판정이
같은 계산(board)을 쓴다. 칸은 회차 전용 코스 스탬프라 러닝위크 기간의 완주만 칸을 채운다.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import coupon_rules, stamp_rules
from app.models import RunningWeek, Stamp, StampDefinition
from app.routers.stamps import definition_to_out
from app.schemas import BINGO_SIZE

# 가로·세로·대각선 줄 수(5x5면 12). 다 채우면 판 전체 = 25칸 = 25개 코스 완주.
MAX_LINES = BINGO_SIZE * 2 + 2

_LINES = (
    [[r * BINGO_SIZE + c for c in range(BINGO_SIZE)] for r in range(BINGO_SIZE)]
    + [[r * BINGO_SIZE + c for r in range(BINGO_SIZE)] for c in range(BINGO_SIZE)]
    + [
        [i * BINGO_SIZE + i for i in range(BINGO_SIZE)],
        [i * BINGO_SIZE + (BINGO_SIZE - 1 - i) for i in range(BINGO_SIZE)],
    ]
)


def completed_lines(acquired: list[bool]) -> int:
    """가로·세로·대각선 중 다 채운 줄 수. 칸 수가 25가 아니면 0."""
    if len(acquired) != BINGO_SIZE * BINGO_SIZE:
        return 0
    return sum(1 for line in _LINES if all(acquired[i] for i in line))


def board(db: Session, week: RunningWeek, user_id: str) -> dict | None:
    """빙고판 25칸과 칸별 획득 여부, 완성 줄 수. 배치를 아직 안 짰으면 None."""
    raw_ids = week.bingo_stamp_ids or []
    if not raw_ids:
        return None
    ids = [uuid.UUID(str(raw)) for raw in raw_ids]

    definitions = {
        d.id: d
        for d in db.execute(
            select(StampDefinition).where(
                StampDefinition.id.in_(ids), StampDefinition.is_active.is_(True)
            )
        ).scalars()
    }
    mine = set(
        db.execute(
            select(Stamp.stamp_definition_id).where(
                Stamp.user_id == user_id, Stamp.stamp_definition_id.in_(ids)
            )
        ).scalars()
    )

    cells = []
    for position, definition_id in enumerate(ids):
        definition = definitions.get(definition_id)
        cells.append(
            {
                "position": position,
                "stamp": definition_to_out(definition) if definition else None,
                "acquired": definition is not None and definition_id in mine,
            }
        )
    return {
        "cells": cells,
        "completed_lines": completed_lines([cell["acquired"] for cell in cells]),
    }


def grant_rewards(
    db: Session, user_id: str, week: RunningWeek, run_id: uuid.UUID | None
) -> None:
    """줄 수만큼 빙고 스탬프를, 판을 다 채웠으면 스페셜 쿠폰을 준다. 커밋은 부르는 쪽이 한다."""
    # 같은 요청에서 막 발급한 코스 스탬프까지 세야 한다.
    db.flush()
    current = board(db, week, user_id)
    if current is None:
        return
    stamp_rules.on_bingo_progress(db, user_id, week.id, current["completed_lines"], run_id)
    if all(cell["acquired"] for cell in current["cells"]):
        coupon_rules.on_bingo_completed(db, user_id, week.id, run_id)
