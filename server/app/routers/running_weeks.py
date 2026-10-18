"""러닝위크(#70) — 앱용 조회·참가 신청. 운영툴은 app.admin.running_weeks에 있다.

빙고 칸이 채워졌는지는 저장하지 않고 조회 때 발급 기록(stamps)에서 계산한다.
러닝위크 전에 받은 스탬프도 인정한다.
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import RunningWeek, RunningWeekParticipation, Stamp, StampDefinition
from app.routers.stamps import definition_to_out
from app.schemas import (
    BINGO_SIZE,
    PARTICIPATION_FORM_VERSION,
    RunningWeekOut,
    RunningWeekParticipationCreate,
)

router = APIRouter(tags=["running-weeks"])

# 참가 정보 보관 기간. 동의 문구(앱 참가 폼)와 같아야 한다.
PARTICIPATION_RETENTION = timedelta(days=365)


def is_visible(week: RunningWeek, now: datetime) -> bool:
    """공지와 같은 규칙. 꺼져 있거나 공개 기간 밖이면 앱에 안 뜬다."""
    if not week.is_active:
        return False
    if week.starts_at is not None and week.starts_at > now:
        return False
    if week.ends_at is not None and week.ends_at < now:
        return False
    return True


def current_week(db: Session) -> RunningWeek | None:
    """지금 공개 중인 러닝위크. 여럿이면 가장 늦게 시작한 회차."""
    now = datetime.now(timezone.utc)
    weeks = db.execute(
        select(RunningWeek).order_by(
            RunningWeek.starts_at.desc().nulls_last(), RunningWeek.created_at.desc()
        )
    ).scalars()
    return next((week for week in weeks if is_visible(week, now)), None)


def completed_lines(acquired: list[bool]) -> int:
    """가로·세로·대각선 중 다 채운 줄 수. 칸 수가 25가 아니면 0."""
    n = BINGO_SIZE
    if len(acquired) != n * n:
        return 0
    lines = [[r * n + c for c in range(n)] for r in range(n)]
    lines += [[r * n + c for r in range(n)] for c in range(n)]
    lines += [[i * n + i for i in range(n)], [i * n + (n - 1 - i) for i in range(n)]]
    return sum(1 for line in lines if all(acquired[i] for i in line))


def bingo_for(db: Session, week: RunningWeek, user_id: str) -> dict | None:
    """빙고판 25칸과 칸별 획득 여부. 배치를 아직 안 짰으면 None."""
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


def purge_expired_participations(db: Session) -> int:
    """보관 기간(1년)이 지난 참가 정보를 지운다. 지운 행 수."""
    result = db.execute(
        delete(RunningWeekParticipation).where(
            RunningWeekParticipation.expires_at < datetime.now(timezone.utc)
        )
    )
    db.commit()
    return result.rowcount or 0


def _participated(db: Session, week_id: uuid.UUID, user_id: str) -> bool:
    return (
        db.execute(
            select(RunningWeekParticipation.id).where(
                RunningWeekParticipation.running_week_id == week_id,
                RunningWeekParticipation.user_id == user_id,
            )
        ).first()
        is not None
    )


def _to_out(db: Session, week: RunningWeek, user_id: str) -> dict:
    participated = _participated(db, week.id, user_id)
    return {
        "id": week.id,
        "title": week.title,
        "description": week.description,
        "image_url": week.image_url,
        "starts_at": week.starts_at,
        "ends_at": week.ends_at,
        "participated": participated,
        # 빙고판은 참가 신청을 해야 볼 수 있다.
        "bingo": bingo_for(db, week, user_id) if participated else None,
    }


@router.get("/running-weeks/current", response_model=RunningWeekOut | None)
def get_current_running_week(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """지금 공개 중인 러닝위크. 없으면 null — 앱은 커뮤니티 배너를 숨긴다."""
    week = current_week(db)
    if week is None:
        return None
    return _to_out(db, week, user_id)


@router.post(
    "/running-weeks/{week_id}/participations",
    response_model=RunningWeekOut,
    status_code=201,
)
def participate(
    week_id: uuid.UUID,
    payload: RunningWeekParticipationCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """참가 신청. 공개 중인 회차만 받고, 한 사람이 두 번 신청하면 409."""
    week = db.get(RunningWeek, week_id)
    if week is None or not is_visible(week, datetime.now(timezone.utc)):
        raise HTTPException(status_code=404, detail="진행 중인 러닝위크가 아니에요.")

    if _participated(db, week.id, user_id):
        raise HTTPException(status_code=409, detail="이미 참가 신청을 했어요.")

    now = datetime.now(timezone.utc)
    db.add(
        RunningWeekParticipation(
            running_week_id=week.id,
            user_id=user_id,
            name=payload.name,
            phone=payload.phone,
            gender=payload.gender,
            age=payload.age,
            residence=payload.residence,
            form_version=PARTICIPATION_FORM_VERSION,
            agreed_at=now,
            expires_at=now + PARTICIPATION_RETENTION,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        # 동시에 두 번 눌러 유일 조건에 걸린 경우.
        db.rollback()
        raise HTTPException(status_code=409, detail="이미 참가 신청을 했어요.") from None

    return _to_out(db, week, user_id)
