"""러닝위크(#70) — 앱용 조회·참가 신청 API. 운영툴은 app.admin.running_weeks에 있다.

기간 판단·보상은 app.running_week, 빙고판 계산은 app.bingo에 있다.
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import bingo, running_week
from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import RunningWeek, RunningWeekParticipation
from app.schemas import (
    PARTICIPATION_FORM_VERSION,
    RunningWeekOut,
    RunningWeekParticipationCreate,
)

router = APIRouter(tags=["running-weeks"])

# 참가 정보 보관 기간. 동의 문구(앱 참가 폼)와 같아야 한다. 지난 행은 운영자가 직접 지운다.
PARTICIPATION_RETENTION = timedelta(days=365)


def _to_out(db: Session, week: RunningWeek, user_id: str) -> dict:
    participated = running_week.participated(db, week.id, user_id)
    return {
        "id": week.id,
        "title": week.title,
        "description": week.description,
        "image_url": week.image_url,
        "starts_at": week.starts_at,
        "ends_at": week.ends_at,
        "participated": participated,
        # 빙고판은 참가 신청을 해야 볼 수 있다.
        "bingo": bingo.board(db, week, user_id) if participated else None,
    }


@router.get("/running-weeks/current", response_model=RunningWeekOut | None)
def get_current_running_week(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
    is_admin: bool = Depends(current_user_is_admin),
):
    """지금 공개 중인 러닝위크. 없으면 null — 앱은 커뮤니티 배너를 숨긴다."""
    week = running_week.current_week(db, is_admin=is_admin)
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
    is_admin: bool = Depends(current_user_is_admin),
):
    """참가 신청. 공개 중인 회차만 받고, 한 사람이 두 번 신청하면 409."""
    week = db.get(RunningWeek, week_id)
    if week is None or not running_week.is_visible(
        week, datetime.now(timezone.utc), is_admin=is_admin
    ):
        raise HTTPException(status_code=404, detail="진행 중인 러닝위크가 아니에요.")

    if running_week.participated(db, week.id, user_id):
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
