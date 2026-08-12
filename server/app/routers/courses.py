import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import gpx
from app.db import get_db
from app.deps import current_user_id, require_admin
from app.models import Course, Stamp
from app.schemas import CourseListItem, CourseSummary, Difficulty

router = APIRouter(tags=["courses"])

# 업로드 가능한 GPX 최대 크기. 6.2km 코스가 36KB이므로 넉넉하다.
# 제한이 없으면 거대한 파일 하나로 워커 메모리를 채울 수 있다.
MAX_GPX_BYTES = 5 * 1024 * 1024


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
    parking_address: str | None,
    restroom_address: str | None,
    description: str | None,
    created_by: str | None,
) -> Course:
    """GPX 바이트를 파싱해 코스를 새로 등록한다.

    `POST /courses/gpx`(HTTP)와 `tools/push_courses.py`(DB 직접 접근)가 공유하는
    단일 진입점이다. 검증 규칙이 한 곳에만 있어야, 스크립트가 API를 거치지 않고
    DB에 바로 써도 규칙이 두 벌로 갈라지지 않는다.

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
        parking_address=parking_address,
        restroom_address=restroom_address,
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


@router.post("/courses/gpx", response_model=CourseSummary, status_code=201)
def create_course_from_gpx(
    file: UploadFile = File(..., description="GPX 파일"),
    distance_km: int = Form(..., ge=1, description="왕복 기준 거리(km)"),
    difficulty: Difficulty = Form(..., description="1=★, 2=★★, 3=★★★"),
    address: str = Form(..., min_length=1, description="코스 시작 지점 주소"),
    name: str | None = Form(default=None, description="생략하면 GPX의 <name>을 쓴다"),
    tags: str | None = Form(default=None, description='쉼표로 구분 — "해안도로,제주시"'),
    parking_address: str | None = Form(default=None, description="근처 주차장 주소"),
    restroom_address: str | None = Form(default=None, description="근처 화장실 주소"),
    description: str | None = Form(default=None),
    db: Session = Depends(get_db),
    user_id: str = Depends(require_admin),
):
    """GPX로 코스를 등록한다. **관리자 전용.**

    거리·난이도·주소는 GPX에서 알 수 없으므로 폼으로 받는다. 특히 거리는 GPX를
    실측한 값이 아니라 코스 명단에 적힌 왕복 안내값이다.
    """
    content = file.file.read(MAX_GPX_BYTES + 1)
    if len(content) > MAX_GPX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"GPX 파일이 너무 커요. {MAX_GPX_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )

    try:
        course = create_course_from_gpx_bytes(
            db,
            content,
            name=name,
            distance_km=distance_km,
            difficulty=difficulty,
            address=address,
            tags=tags,
            parking_address=parking_address,
            restroom_address=restroom_address,
            description=description,
            created_by=user_id,
        )
    except CourseUploadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    # 방금 만든 코스라 완주자는 아직 없다.
    return _to_summary(course, 0, False)
