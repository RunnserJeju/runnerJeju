import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Stamp
from app.schemas import CourseCreate, CourseSummary

router = APIRouter(tags=["courses"])


def _to_summary(course: Course, completed_count: int, is_completed_by_me: bool) -> dict:
    return {
        "id": course.id,
        "name": course.name,
        "description": course.description,
        "region": course.region,
        "difficulty": course.difficulty,
        "distance_meters": course.distance_meters,
        "estimated_duration_sec": course.estimated_duration_sec,
        "elevation_gain_meters": course.elevation_gain_meters,
        "thumbnail_url": course.thumbnail_url,
        "path": course.path or [],
        "completed_count": completed_count,
        "is_completed_by_me": is_completed_by_me,
    }


def _completed_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 완주자 수를 한 번에 조회한다(목록에서 N+1을 피하려고)."""
    if not course_ids:
        return {}

    rows = db.execute(
        select(Stamp.course_id, func.count(Stamp.id))
        .where(Stamp.course_id.in_(course_ids))
        .group_by(Stamp.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


def _my_completed_course_ids(
    db: Session, user_id: str, course_ids: list[uuid.UUID]
) -> set[uuid.UUID]:
    if not course_ids:
        return set()

    rows = db.execute(
        select(Stamp.course_id).where(
            Stamp.user_id == user_id, Stamp.course_id.in_(course_ids)
        )
    ).scalars()

    return set(rows)


@router.get("/courses", response_model=list[CourseSummary])
def list_courses(
    region: str | None = Query(default=None),
    keyword: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    stmt = select(Course).order_by(Course.created_at.desc())

    if region:
        stmt = stmt.where(Course.region == region)
    if keyword:
        stmt = stmt.where(Course.name.ilike(f"%{keyword}%"))

    courses = list(db.execute(stmt).scalars())
    course_ids = [course.id for course in courses]

    counts = _completed_counts(db, course_ids)
    mine = _my_completed_course_ids(db, user_id, course_ids)

    return [
        _to_summary(course, counts.get(course.id, 0), course.id in mine)
        for course in courses
    ]


@router.get("/courses/{course_id}", response_model=CourseSummary)
def get_course(
    course_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    course = db.get(Course, course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    counts = _completed_counts(db, [course.id])
    mine = _my_completed_course_ids(db, user_id, [course.id])

    return _to_summary(course, counts.get(course.id, 0), course.id in mine)


@router.post("/courses", response_model=CourseSummary, status_code=201)
def create_course(
    payload: CourseCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    if len(payload.path) < 2:
        raise HTTPException(
            status_code=422, detail="코스로 등록하려면 경로가 2개 지점 이상이어야 해요."
        )

    course = Course(
        name=payload.name,
        description=payload.description,
        region=payload.region,
        difficulty=payload.difficulty,
        distance_meters=payload.distance_meters,
        path=[point.model_dump(mode="json") for point in payload.path],
        created_by=user_id,
    )

    db.add(course)
    db.commit()
    db.refresh(course)

    # 방금 만든 코스라 완주자는 아직 없다.
    return _to_summary(course, 0, False)
