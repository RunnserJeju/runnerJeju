import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Run
from app.schemas import RunCreate, RunOut, RunUploadResult

router = APIRouter(tags=["runs"])


def to_run_out(run: Run) -> dict:
    return {
        "id": run.id,
        "course_id": run.course_id,
        "course_name": run.course.name if run.course else None,
        "started_at": run.started_at,
        "ended_at": run.ended_at,
        "distance_meters": run.distance_meters,
        "duration_sec": run.duration_sec,
        "path": run.path or [],
    }


@router.post("/runs", response_model=RunUploadResult, status_code=201)
def create_run(
    payload: RunCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """러닝 기록 저장.

    여기서는 검증을 하지 않는다. 경로 검증은 CPU를 오래 쓰는 작업이라
    별도 엔드포인트(POST /runs/{id}/verification)로 분리해 두었고,
    스탬프도 그 검증 결과로만 발급된다.
    """
    if payload.course_id is not None and db.get(Course, payload.course_id) is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    if payload.ended_at < payload.started_at:
        raise HTTPException(status_code=422, detail="종료 시각이 시작 시각보다 빨라요.")

    run = Run(
        user_id=user_id,
        course_id=payload.course_id,
        started_at=payload.started_at,
        ended_at=payload.ended_at,
        distance_meters=payload.distance_meters,
        duration_sec=payload.duration_sec,
        path=[point.model_dump(mode="json") for point in payload.path],
    )

    db.add(run)
    db.commit()
    db.refresh(run)

    return {"record": to_run_out(run), "earned_stamp_id": None}


@router.get("/runs", response_model=list[RunOut])
def list_runs(
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    runs = db.execute(
        select(Run)
        .where(Run.user_id == user_id)
        .order_by(Run.started_at.desc())
        .limit(limit)
    ).scalars()

    return [to_run_out(run) for run in runs]


@router.get("/runs/{run_id}", response_model=RunOut)
def get_run(
    run_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    run = db.get(Run, run_id)
    if run is None or run.user_id != user_id:
        raise HTTPException(status_code=404, detail="러닝 기록을 찾을 수 없어요.")

    return to_run_out(run)
