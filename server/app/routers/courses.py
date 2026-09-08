import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app import gpx
from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import Course, CourseView, Stamp
from app.schemas import CourseListItem, CourseSummary

router = APIRouter(tags=["courses"])

# 조회수 '하루' 경계는 한국 시간(KST) 기준. 한국은 DST가 없어 고정 오프셋(UTC+9)이면
# 정확하고, tzdata 의존도 없다.
KST = timezone(timedelta(hours=9))


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
        "estimated_time_min": course.estimated_time_min,
        "thumbnail_url": course.thumbnail_url,
        "stamp_image_url": course.stamp_image_url,
        "path": path,
        # 목록 응답(CourseListItem)에는 path가 빠지므로, 지도에 라벨을 찍을 점은
        # 여기서 따로 뽑아 준다. 상세 응답에도 같이 들어가지만 값은 path[0]과
        # 같아서 클라이언트가 둘 중 무엇을 봐도 결과가 다르지 않다.
        "start_point": path[0] if path else None,
        "completed_count": completed_count,
        "is_completed_by_me": is_completed_by_me,
        "visibility": course.visibility,
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


def _record_view(db: Session, course_id: uuid.UUID, user_id: str) -> None:
    """코스 상세 조회를 하루 1회로 기록한다(중복제거). GET /courses/{id}의 부수효과.

    같은 (코스, 사용자, 날짜)면 ON CONFLICT DO NOTHING으로 조용히 넘어가, 하루에 같은
    코스를 여러 번 열어도 조회수는 1만 는다 — 조회수는 코스별 '고유 조회(사람·일)'다.
    '하루'는 KST 기준(view_date). 분석용 쓰기라 **best-effort** — 실패하면 롤백만 하고
    상세 조회(핵심 읽기)는 성공시킨다.
    """
    stmt = (
        pg_insert(CourseView)
        .values(
            course_id=course_id,
            user_id=user_id,
            view_date=datetime.now(KST).date(),
        )
        .on_conflict_do_nothing(index_elements=["course_id", "user_id", "view_date"])
    )
    try:
        db.execute(stmt)
        db.commit()
    except SQLAlchemyError:
        db.rollback()


def visible_courses(stmt, is_admin: bool):
    """일반 사용자에게는 visibility='public'인 코스만. NULL(미설정)도 숨긴다."""
    if is_admin:
        return stmt
    return stmt.where(Course.visibility == "public")


def _escape_like(keyword: str) -> str:
    """사용자 입력의 LIKE 와일드카드(%, _)를 글자 그대로 찾게 한다."""
    return keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/courses", response_model=list[CourseListItem])
def list_courses(
    keyword: str | None = Query(default=None),
    limit: int | None = Query(default=None, ge=1, le=100),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
    is_admin: bool = Depends(current_user_is_admin),
):
    stmt = visible_courses(select(Course), is_admin).order_by(Course.created_at.desc())

    keyword = (keyword or "").strip()
    if keyword:
        stmt = stmt.where(Course.name.ilike(f"%{_escape_like(keyword)}%", escape="\\"))
    if limit is not None:
        stmt = stmt.limit(limit)

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
    is_admin: bool = Depends(current_user_is_admin),
):
    # 숨긴 코스는 없는 것과 같이 404 — 있다는 사실도 알리지 않는다.
    course = db.scalar(
        visible_courses(select(Course).where(Course.id == course_id), is_admin)
    )
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    counts = _completed_counts(db, [course.id])
    mine = _my_completed_course_ids(db, user_id, [course.id])
    summary = _to_summary(course, counts.get(course.id, 0), course.id in mine)

    # 응답을 다 만든 뒤 조회를 기록한다 — 여기 commit이 세션을 expire시켜도 이미 dict로
    # 뽑아둔 summary엔 영향이 없고(course 재로딩 없음), best-effort라 기록 실패가 상세
    # 조회를 깨지 않는다. 존재하는 코스만 센다.
    _record_view(db, course.id, user_id)

    return summary


class CourseUploadError(Exception):
    """GPX 업로드 검증 실패. HTTP 라우터와 tools/push_courses.py가 각자 방식으로 처리한다."""


def _parse_gpx_or_raise(content: bytes):
    """GPX 바이트를 파싱해 반환한다. 빈 파일·파싱 실패는 CourseUploadError로 통일한다.

    코스 신규 등록(create_course_from_gpx_bytes)과 경로 교체(PUT /courses/{id}/gpx)가
    공유한다 — 파싱 규칙이 한 곳에만 있게.
    """
    if not content:
        raise CourseUploadError("빈 파일이에요.")
    try:
        return gpx.parse(content)
    except gpx.GpxParseError as exc:
        raise CourseUploadError(str(exc)) from exc


def resample_path_from_gpx(content: bytes) -> list:
    """GPX에서 균등 간격으로 리샘플한 경로(JSON 점 목록)를 만든다.

    원본 GPX 점이 아니라 리샘플한 점을 쓰는 이유는 등록과 같다 — 검증 매칭률이
    "코스 거리의 몇 %"와 일치하려면 점 밀도가 균등해야 하고, 클라이언트도 이 경로를
    실시간 커버리지 계산의 기준점으로 쓴다. 경로 교체 엔드포인트가 이 함수를 쓴다.
    """
    parsed = _parse_gpx_or_raise(content)
    return [point.to_json() for point in parsed.resampled_points]


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
    estimated_time_min: int | None = None,
    # 운영 웹은 필수로 받고, 시드 스크립트는 안 넘겨 NULL(미설정)로 올라간다.
    visibility: str | None = None,
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
    parsed = _parse_gpx_or_raise(content)

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
        estimated_time_min=estimated_time_min,
        visibility=visibility,
        # 썸네일(thumbnail_url)은 여기서 안 넣는다 — 파일 업로드가 필요해 등록 직후
        # 전용 엔드포인트가 따로 채운다. 새 코스는 항상 썸네일 없이 만들어진다.
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
