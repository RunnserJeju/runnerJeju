import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import gpx
from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Stamp
from app.schemas import CourseListItem, CourseSummary

router = APIRouter(tags=["courses"])


def _to_summary(course: Course, completed_count: int, is_completed_by_me: bool) -> dict:
    path = course.path or []

    return {
        "id": course.id,
        "name": course.name,
        "distance_km": course.distance_km,
        "difficulty": course.difficulty,
        "tags": course.tags,
        "address": course.address,
        "parking_address": course.parking_address,
        "restroom_address": course.restroom_address,
        "parkings": course.parkings or [],
        "restrooms": course.restrooms or [],
        "description": course.description,
        "path": path,
        # 목록 응답(CourseListItem)에는 path가 빠지므로, 지도에 라벨을 찍을 점은
        # 여기서 따로 뽑아 준다. 상세 응답에도 같이 들어가지만 값은 path[0]과
        # 같아서 클라이언트가 둘 중 무엇을 봐도 결과가 다르지 않다.
        "start_point": path[0] if path else None,
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


@router.get("/courses", response_model=list[CourseListItem])
def list_courses(
    keyword: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    stmt = select(Course).order_by(Course.created_at.desc())

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


class CourseUploadError(Exception):
    """GPX 업로드 검증 실패. HTTP 라우터와 tools/push_courses.py가 각자 방식으로 처리한다."""


def create_course_from_gpx_bytes(
    db: Session,
    content: bytes,
    *,
    name: str | None,
    distance_km: int,
    difficulty: int,
    address: str,
    tags: str | None,
    parkings: list[dict] | None = None,
    restrooms: list[dict] | None = None,
    description: str | None,
    created_by: str | None,
) -> Course:
    """GPX 바이트를 파싱해 코스를 새로 등록한다.

    `POST /courses/gpx`(HTTP)와 `tools/push_courses.py`(DB 직접 접근)가 공유하는
    단일 진입점이다. 검증 규칙이 한 곳에만 있어야, 스크립트가 API를 거치지 않고
    DB에 바로 써도 규칙이 두 벌로 갈라지지 않는다.

    parkings/restrooms는 각 원소가 {"name", "address", "lat", "lng"}인 dict 목록이다.
    좌표 변환은 호출하는 쪽 책임이다 — HTTP는 클라이언트가 "확인"으로 채워 보내고,
    스크립트는 push 시점에 geocode한다. 이 함수는 좌표를 그대로 저장만 하므로
    네트워크에 의존하지 않는다(테스트가 쉬워진다).

    같은 GPX를 다시 올리면 코스가 하나 더 생긴다 — 갱신이 아니다. 코스를 고칠
    일은 DB에서 직접 처리하기로 했으므로, 다시 올릴 때는 먼저 지우면 된다.
    """
    if not content:
        raise CourseUploadError("빈 파일이에요.")

    try:
        parsed = gpx.parse(content)
    except gpx.GpxParseError as exc:
        raise CourseUploadError(str(exc)) from exc

    resolved_name = name or parsed.name
    if not resolved_name:
        raise CourseUploadError(
            "코스 이름이 없어요. GPX에 <name>이 없다면 name 필드로 넘겨주세요."
        )

    course = Course(
        name=resolved_name,
        distance_km=distance_km,
        difficulty=difficulty,
        address=address,
        tags=tags,
        parkings=parkings or [],
        restrooms=restrooms or [],
        description=description,
        # 원본 GPX 점이 아니라 균등 간격으로 리샘플한 경로를 저장한다.
        # 검증 매칭률이 "코스 거리의 몇 %"와 일치하려면 점 밀도가 균등해야 하고,
        # 클라이언트도 이 경로를 그대로 받아 실시간 커버리지 계산의 기준점으로 쓴다.
        path=[point.to_json() for point in parsed.resampled_points],
        created_by=created_by,
    )

    db.add(course)
    db.commit()
    db.refresh(course)

    return course
