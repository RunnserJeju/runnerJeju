import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import gpx
from app.db import get_db
from app.deps import current_user_id
from app.models import Course, Stamp
from app.schemas import CourseCreate, CourseListItem, CourseSummary, Difficulty

router = APIRouter(tags=["courses"])

# 업로드 가능한 GPX 최대 크기. 6.2km 코스가 36KB이므로 넉넉하다.
# 제한이 없으면 거대한 파일 하나로 워커 메모리를 채울 수 있다.
MAX_GPX_BYTES = 5 * 1024 * 1024


def _to_summary(course: Course, completed_count: int, is_completed_by_me: bool) -> dict:
    return {
        "id": course.id,
        "slug": course.slug,
        "name": course.name,
        "description": course.description,
        "region": course.region,
        "difficulty": course.difficulty,
        "distance_meters": course.distance_meters,
        "estimated_duration_sec": course.estimated_duration_sec,
        "elevation_gain_meters": course.elevation_gain_meters,
        "thumbnail_url": course.thumbnail_url,
        "path": course.path or [],
        "is_loop": course.is_loop,
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


def _unique_slug(db: Session, base: str) -> str:
    """base가 이미 쓰이고 있으면 뒤에 숫자를 붙여 비어 있는 slug를 찾는다."""
    base = base or "course"
    candidate = base
    suffix = 2

    while db.execute(select(Course.id).where(Course.slug == candidate)).first():
        candidate = f"{base}-{suffix}"
        suffix += 1

    return candidate


@router.get("/courses", response_model=list[CourseListItem])
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
        # 앱은 slug를 모른다(달린 경로를 그대로 올리는 화면이라 코스 식별자 개념이 없다).
        # 이름에서 만들어 붙이되, 겹치면 뒤에 숫자를 붙여 유니크를 지킨다.
        slug=_unique_slug(db, gpx.slugify(payload.name)),
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


class CourseUploadError(Exception):
    """GPX 업로드 검증 실패. HTTP 라우터와 tools/push_courses.py가 각자 방식으로 처리한다."""


def upsert_course_from_gpx_bytes(
    db: Session,
    content: bytes,
    *,
    slug: str | None,
    name: str | None,
    description: str | None,
    region: str | None,
    difficulty: str,
    estimated_duration_sec: int | None,
    thumbnail_url: str | None,
    created_by: str | None,
) -> tuple[Course, bool]:
    """GPX 바이트를 파싱해 코스를 등록/갱신한다. (course, is_new)를 돌려준다.

    `PUT /courses/gpx`(HTTP)와 `tools/push_courses.py`(DB 직접 접근)가 공유하는
    단일 진입점이다. 검증 규칙이 한 곳에만 있어야, 스크립트가 API를 거치지 않고
    DB에 바로 써도 규칙이 두 벌로 갈라지지 않는다.

    slug를 생략하면(예: 앱 내 즉석 업로드) 재업로드 개념이 없으니 이름에서
    매번 새 slug를 만든다 — 그래서 항상 새 코스가 생긴다.
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

    if slug is None:
        slug = _unique_slug(db, gpx.slugify(resolved_name))

    course = db.execute(select(Course).where(Course.slug == slug)).scalar_one_or_none()
    is_new = course is None

    if course is None:
        course = Course(slug=slug, created_by=created_by)
        db.add(course)

    course.name = resolved_name
    course.description = description
    course.region = region
    course.difficulty = difficulty
    course.estimated_duration_sec = estimated_duration_sec
    course.thumbnail_url = thumbnail_url

    course.path = [point.to_json() for point in parsed.points]
    course.distance_meters = parsed.distance_meters
    course.elevation_gain_meters = parsed.elevation_gain_meters
    course.is_loop = parsed.is_loop

    db.commit()
    db.refresh(course)

    return course, is_new


@router.put("/courses/gpx", response_model=CourseSummary)
def upsert_course_from_gpx(
    response: Response,
    file: UploadFile = File(..., description="GPX 파일"),
    slug: str | None = Form(
        default=None,
        description="코스의 안정적인 식별자. 재업로드 시 이 값으로 찾는다. 생략하면 이름에서 자동 생성한다(항상 새 코스)",
    ),
    name: str | None = Form(default=None, description="생략하면 GPX의 <name>을 쓴다"),
    description: str | None = Form(default=None),
    region: str | None = Form(default=None),
    difficulty: Difficulty = Form(default="normal"),
    estimated_duration_sec: int | None = Form(default=None),
    thumbnail_url: str | None = Form(default=None),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """GPX로 코스를 등록하거나 갱신한다.

    POST가 아니라 PUT인 이유는 이 연산이 멱등이기 때문이다. 같은 slug로 같은 파일을
    몇 번을 올려도 코스는 하나이고 결과도 같다. 재업로드가 새 코스를 만들면
    stamps.course_id가 가리키던 완주 스탬프가 고아가 되므로 갱신이어야 한다.

    거리와 고도는 폼으로 받지 않고 GPX에서 계산한다. 파일과 어긋난 값이 들어오는
    경로를 아예 만들지 않기 위해서다.
    """
    content = file.file.read(MAX_GPX_BYTES + 1)
    if len(content) > MAX_GPX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"GPX 파일이 너무 커요. {MAX_GPX_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )

    try:
        course, is_new = upsert_course_from_gpx_bytes(
            db,
            content,
            slug=slug,
            name=name,
            description=description,
            region=region,
            difficulty=difficulty,
            estimated_duration_sec=estimated_duration_sec,
            thumbnail_url=thumbnail_url,
            created_by=user_id,
        )
    except CourseUploadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    response.status_code = 201 if is_new else 200

    counts = _completed_counts(db, [course.id])
    mine = _my_completed_course_ids(db, user_id, [course.id])

    return _to_summary(course, counts.get(course.id, 0), course.id in mine)
