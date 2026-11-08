import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Run, Verification
from app import run_continuation
from app.routers.verifications import earned_stamp_id, verify_run
from app.run_continuation import continuable_since
from app.schemas import RunContinue, RunCreate, RunOut, RunUploadResult

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


def to_run_out(
    run: Run,
    with_path: bool = True,
    completed: bool = False,
    match_rate: float | None = None,
) -> dict:
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
        "match_rate": match_rate,
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


@router.post("/runs/{run_id}/continue", response_model=RunUploadResult)
def continue_run(
    run_id: uuid.UUID,
    payload: RunContinue,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """이어달리기: 미완주 코스 러닝 뒤에 새로 달린 구간을 붙이고 완주 검증을 다시 한다.

    같은 기록 하나로 이어진다(새 기록을 만들지 않는다). 스탬프·쿠폰이 run_id를 가리키므로
    완주가 되면 보상도 이 기록 앞으로 나간다. 응답 모양은 POST /runs와 같다.
    """
    # 같은 기록에 두 구간이 동시에 붙으면(두 기기, 재시도 경합) 한쪽이 덮인다. 잠그고 읽는다.
    run = db.execute(
        select(Run).where(Run.id == run_id).with_for_update()
    ).scalar_one_or_none()
    if run is None or run.user_id != user_id:
        raise HTTPException(status_code=404, detail="러닝 기록을 찾을 수 없어요.")

    # 재시도로 같은 구간이 다시 왔다. 이미 붙었으니 지금 상태를 그대로 돌려준다 —
    # 그 구간으로 완주했어도 아래 '이미 완주' 검사에 걸리지 않게 가장 먼저 본다.
    if run_continuation.has_segment(run, payload.segment_id):
        completed = run.id in _completed_run_ids(db, [run.id])
        return {
            "record": to_run_out(run, completed=completed),
            "earned_stamp_id": (
                earned_stamp_id(db, run.id, run.course_id) if completed else None
            ),
        }

    course = run.course
    if course is None:
        raise HTTPException(status_code=422, detail="코스 러닝만 이어 달릴 수 있어요.")

    previous = db.execute(
        select(Verification).where(
            Verification.run_id == run.id, Verification.course_id == course.id
        )
    ).scalar_one_or_none()
    if previous is not None and previous.status == "matched":
        raise HTTPException(status_code=409, detail="이미 완주한 기록이에요.")

    if payload.ended_at < payload.started_at:
        raise HTTPException(status_code=422, detail="종료 시각이 시작 시각보다 빨라요.")
    if payload.started_at < run.started_at:
        raise HTTPException(status_code=422, detail="원래 기록보다 먼저 시작한 구간이에요.")
    if not run_continuation.is_continuable(run.started_at, at=payload.started_at):
        raise HTTPException(
            status_code=409, detail="이어 달릴 수 있는 기간(7일)이 지났어요."
        )
    if payload.distance_meters <= run_continuation.MIN_SEGMENT_METERS:
        raise HTTPException(status_code=422, detail="이어 달린 거리가 너무 짧아요.")

    run_continuation.append_segment(run, payload, now=datetime.now(timezone.utc))

    # 검증은 (run, course)당 하나라 캐시된 미완주 결과가 있으면 새 경로로 다시 재지
    # 않는다(verify_run). 지우고 다시 만든다.
    if previous is not None:
        db.delete(previous)
        db.flush()

    verification = None
    try:
        verification = verify_run(db, user_id, run, course)
    except Exception:
        # 검증이 터져도 이어 붙인 기록은 남아야 한다. 앱의 후속 검증 요청이 다시 시도한다.
        logger.exception("이어달리기 검증 실패 run=%s course=%s", run.id, course.id)
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


# /runs/{run_id}보다 먼저 등록해야 한다. 뒤에 있으면 "continuable"을 run_id로 읽고 422를 낸다.
@router.get("/runs/continuable", response_model=list[RunOut])
def list_continuable_runs(
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """이어 달릴 수 있는 기록(최근 순, 경로 없이): 최근 7일(KST) 안에 시작한 미완주 코스 러닝.

    기간 경계는 서버 시각으로 정한다(run_continuation). 앱 시계·시간대와 무관하게
    이어 붙일 때의 판정과 같은 결과가 나온다.
    """
    since = continuable_since(datetime.now(timezone.utc))
    # (run, course) 검증은 하나뿐이라 outer join으로 행이 늘지 않는다. 검증이 없는
    # 기록(업로드 때 검증이 실패한 옛 데이터)도 미완주로 친다.
    rows = db.execute(
        select(Run, Verification.match_rate)
        .outerjoin(
            Verification,
            (Verification.run_id == Run.id) & (Verification.course_id == Run.course_id),
        )
        .where(
            Run.user_id == user_id,
            Run.course_id.is_not(None),
            Run.started_at >= since,
            or_(Verification.status.is_(None), Verification.status != "matched"),
        )
        .options(selectinload(Run.course))
        .order_by(Run.started_at.desc())
        .limit(limit)
    ).all()

    return [
        to_run_out(run, with_path=False, match_rate=match_rate)
        for run, match_rate in rows
    ]


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
