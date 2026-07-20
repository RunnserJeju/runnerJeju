import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import verification as verification_logic
from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Run, Stamp, Verification
from app.schemas import VerificationCreate, VerificationOut

router = APIRouter(tags=["verifications"])


def _earned_stamp_id(db: Session, user_id: str, course_id: uuid.UUID) -> uuid.UUID | None:
    stamp = db.execute(
        select(Stamp).where(Stamp.user_id == user_id, Stamp.course_id == course_id)
    ).scalar_one_or_none()

    return stamp.id if stamp else None


def _to_out(db: Session, verification: Verification, user_id: str) -> dict:
    stamp_id = (
        _earned_stamp_id(db, user_id, verification.course_id)
        if verification.status == "matched"
        else None
    )

    return {
        "id": verification.id,
        "run_id": verification.run_id,
        "course_id": verification.course_id,
        "status": verification.status,
        "match_rate": verification.match_rate,
        "detail": verification.detail,
        "completed_at": verification.completed_at,
        "earned_stamp_id": stamp_id,
    }


def _issue_stamp(db: Session, user_id: str, run: Run, course: Course) -> None:
    """완주 스탬프 발급. 같은 코스를 다시 완주해도 스탬프는 하나만 유지한다."""
    existing = db.execute(
        select(Stamp).where(Stamp.user_id == user_id, Stamp.course_id == course.id)
    ).scalar_one_or_none()

    if existing is not None:
        return

    db.add(Stamp(user_id=user_id, course_id=course.id, run_id=run.id))


@router.post("/runs/{run_id}/verification", response_model=VerificationOut, status_code=201)
def request_verification(
    run_id: uuid.UUID,
    payload: VerificationCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """경로 검증 요청.

    지금은 FastAPI가 검증까지 동기로 계산해 결과를 바로 돌려준다.
    검증 서버를 분리하면 여기서 요청만 넘기고 status='pending'으로 응답하게 되며,
    클라이언트는 GET /verifications/{id}로 폴링한다(앱은 이미 그 흐름을 지원한다).
    """
    run = db.get(Run, run_id)
    if run is None or run.user_id != user_id:
        raise HTTPException(status_code=404, detail="러닝 기록을 찾을 수 없어요.")

    course = db.get(Course, payload.course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    # 같은 (러닝, 코스) 조합은 한 번만 계산한다. 앱이 재시도로 다시 호출해도
    # CPU를 또 쓰지 않고 기존 결과를 그대로 돌려준다.
    existing = db.execute(
        select(Verification).where(
            Verification.run_id == run_id, Verification.course_id == course.id
        )
    ).scalar_one_or_none()

    if existing is not None:
        return _to_out(db, existing, user_id)

    outcome = verification_logic.verify(
        course_path=verification_logic.to_points(course.path or []),
        run_path=verification_logic.to_points(run.path or []),
    )

    record = Verification(
        run_id=run.id,
        course_id=course.id,
        status=outcome.status,
        match_rate=outcome.match_rate,
        detail=outcome.detail,
        completed_at=datetime.now(timezone.utc),
    )
    db.add(record)

    if outcome.status == "matched":
        _issue_stamp(db, user_id, run, course)

    db.commit()
    db.refresh(record)

    return _to_out(db, record, user_id)


@router.get("/verifications/{verification_id}", response_model=VerificationOut)
def get_verification(
    verification_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """검증 진행 상태 조회(폴링용)."""
    record = db.get(Verification, verification_id)
    if record is None:
        raise HTTPException(status_code=404, detail="검증 정보를 찾을 수 없어요.")

    if record.run.user_id != user_id:
        raise HTTPException(status_code=404, detail="검증 정보를 찾을 수 없어요.")

    return _to_out(db, record, user_id)
