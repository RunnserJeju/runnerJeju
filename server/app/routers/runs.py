import logging
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Run, Verification
from app.routers.verifications import earned_stamp_id, verify_run
from app.schemas import RunCreate, RunOut, RunUploadResult

logger = logging.getLogger(__name__)
router = APIRouter(tags=["runs"])


def _completed_run_ids(db: Session, run_ids: list[uuid.UUID]) -> set[uuid.UUID]:
    """완주 인증이 통과한(matched) 러닝."""
    if not run_ids:
        return set()
    return set(
        db.execute(
            select(Verification.run_id).where(
                Verification.run_id.in_(run_ids), Verification.status == "matched"
            )
        ).scalars()
    )


def to_run_out(run: Run, with_path: bool = True, completed: bool = False) -> dict:
    return {
        "id": run.id,
        "course_id": run.course_id,
        "course_name": run.course.name if run.course else None,
        "started_at": run.started_at,
        "ended_at": run.ended_at,
        "distance_meters": run.distance_meters,
        "duration_sec": run.duration_sec,
        "path": (run.path or []) if with_path else [],
        "completed": completed,
    }


@router.post("/runs", response_model=RunUploadResult, status_code=201)
def create_run(
    payload: RunCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """러닝 기록 저장. 코스 러닝이면 같은 트랜잭션에서 완주 검증까지 끝낸다.

    검증을 앱의 후속 요청(POST /runs/{id}/verification)에만 맡기면, 앱이 결과 화면을
    저장 중에 닫았을 때 기록만 남고 완주 처리가 영영 안 된다(#104). 그 요청은
    이제 여기서 만든 결과를 그대로 돌려받는다.
    """
    course = None
    if payload.course_id is not None:
        course = db.get(Course, payload.course_id)
        if course is None:
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
        # 기본값인 필드는 빼고 저장한다. 경로 한 벌이 천 점을 넘는데, 그중
        # 대부분은 고도도 없고 끊긴 자리도 아니다 — 그 빈 값을 점마다 실어 두면
        # 그대로 저장 용량이 된다. 읽을 때는 스키마 기본값으로 다시 채워진다.
        path=[
            point.model_dump(mode="json", exclude_defaults=True)
            for point in payload.path
        ],
    )

    db.add(run)
    db.flush()  # run.id 확정
    verification = None
    if course is not None:
        try:
            verification = verify_run(db, user_id, run, course)
        except Exception:
            # 검증이 터져도 기록 저장은 성공해야 한다. 앱의 후속 검증 요청이 다시 시도한다.
            logger.exception("업로드 시 검증 실패 run=%s course=%s", run.id, course.id)
    db.commit()
    db.refresh(run)

    completed = verification is not None and verification.status == "matched"
    return {
        "record": to_run_out(run, completed=completed),
        "earned_stamp_id": earned_stamp_id(db, run.id, course.id) if completed else None,
    }


@router.get("/runs", response_model=list[RunOut])
def list_runs(
    limit: int = Query(default=20, ge=1, le=500),
    since: datetime | None = Query(default=None, description="started_at 이상"),
    until: datetime | None = Query(default=None, description="started_at 미만"),
    with_path: bool = Query(default=True, description="false면 path를 빈 배열로(달력용)"),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    query = select(Run).where(Run.user_id == user_id).options(selectinload(Run.course))
    if since is not None:
        query = query.where(Run.started_at >= since)
    if until is not None:
        query = query.where(Run.started_at < until)
    runs = list(db.execute(query.order_by(Run.started_at.desc()).limit(limit)).scalars())
    completed = _completed_run_ids(db, [run.id for run in runs])

    return [to_run_out(run, with_path, run.id in completed) for run in runs]


@router.get("/runs/{run_id}", response_model=RunOut)
def get_run(
    run_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    run = db.get(Run, run_id)
    if run is None or run.user_id != user_id:
        raise HTTPException(status_code=404, detail="러닝 기록을 찾을 수 없어요.")

    return to_run_out(run, completed=run.id in _completed_run_ids(db, [run.id]))
