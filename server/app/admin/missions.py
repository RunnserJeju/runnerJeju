"""운영자 전용 미션 API — 작성/목록/상세/수정/삭제.

이벤트 미션의 참여 기간·달성 조건·리워드·내용을 운영자가 설정한다. 달성 조건과
리워드는 자유 텍스트이고, 자동 판정(런타임)·유저 참여·리워드 지급은 아직 없다 —
지금은 "정의"까지다. 앱에 노출하는 공개 조회(GET /missions)도 프론트를 붙일 때
따로 만든다.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Mission
from app.schemas import MissionCreate, MissionOut, MissionUpdate

router = APIRouter(tags=["missions"])


def _load_mission_or_404(db: Session, mission_id: uuid.UUID) -> Mission:
    mission = db.get(Mission, mission_id)
    if mission is None:
        raise HTTPException(status_code=404, detail="미션을 찾을 수 없어요.")
    return mission


@router.get("/missions", response_model=list[MissionOut])
def list_missions(db: Session = Depends(get_db)):
    """미션 전체 목록. (관리자 전용 — 라우터 레벨에서 강제)

    비활성·기간이 지난 것까지 다 내려준다 — 운영자는 상태와 무관하게 관리해야 한다.
    정렬은 sort_order 오름차순, 같으면 최신순.
    """
    return list(
        db.execute(
            select(Mission).order_by(Mission.sort_order, Mission.created_at.desc())
        ).scalars()
    )


@router.get("/missions/{mission_id}", response_model=MissionOut)
def get_mission(mission_id: uuid.UUID, db: Session = Depends(get_db)):
    """미션 상세. (관리자 전용 — 라우터 레벨에서 강제)"""
    return _load_mission_or_404(db, mission_id)


@router.post("/missions", response_model=MissionOut, status_code=201)
def create_mission(payload: MissionCreate, db: Session = Depends(get_db)):
    """미션을 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    mission = Mission(
        title=payload.title,
        body=payload.body,
        condition=payload.condition,
        reward=payload.reward,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        is_active=payload.is_active,
        sort_order=payload.sort_order,
    )
    db.add(mission)
    db.commit()
    db.refresh(mission)
    return mission


@router.patch("/missions/{mission_id}", response_model=MissionOut)
def update_mission(
    mission_id: uuid.UUID,
    payload: MissionUpdate,
    db: Session = Depends(get_db),
):
    """미션을 수정한다(전체 교체). (관리자 전용 — 라우터 레벨에서 강제)"""
    mission = _load_mission_or_404(db, mission_id)

    mission.title = payload.title
    mission.body = payload.body
    mission.condition = payload.condition
    mission.reward = payload.reward
    mission.starts_at = payload.starts_at
    mission.ends_at = payload.ends_at
    mission.is_active = payload.is_active
    mission.sort_order = payload.sort_order

    db.commit()
    db.refresh(mission)
    return mission


@router.delete("/missions/{mission_id}", status_code=204)
def delete_mission(mission_id: uuid.UUID, db: Session = Depends(get_db)):
    """미션을 삭제한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    mission = _load_mission_or_404(db, mission_id)
    db.delete(mission)
    db.commit()
