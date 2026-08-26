"""운영자 전용 코스 API — 등록/수정. 공개 조회는 app.routers.courses에 있다.

응답 변환·완주자 조회·GPX 파싱 등 공유 로직은 app.routers.courses가 소유하고
(tools/push_courses.py도 그 진입점을 쓴다) 여기서는 import해 재사용한다.
"""

import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import TypeAdapter, ValidationError
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Course
from app.routers.courses import (
    CourseUploadError,
    _completed_counts,
    _my_completed_course_ids,
    _to_summary,
    create_course_from_gpx_bytes,
)
from app.schemas import CourseSummary, CourseUpdate, Difficulty, Facility

router = APIRouter(tags=["courses"])

# 업로드 가능한 GPX 최대 크기. 6.2km 코스가 36KB이므로 넉넉하다.
# 제한이 없으면 거대한 파일 하나로 워커 메모리를 채울 수 있다.
MAX_GPX_BYTES = 5 * 1024 * 1024

# 멀티파트 폼에 파일과 함께 실려오는 parkings/restrooms를 검증한다. 폼 필드라
# JSON 문자열로 오므로 validate_json으로 파싱한다(각 원소는 Facility = 좌표 포함).
_facility_list = TypeAdapter(list[Facility])


@router.patch("/courses/{course_id}", response_model=CourseSummary)
def update_course(
    course_id: uuid.UUID,
    payload: CourseUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """코스의 메타데이터를 수정한다. (관리자 전용 — 라우터 레벨에서 강제)

    경로(path)·완주 기록·작성자는 건드리지 않는다. 주차장/화장실은 좌표까지
    포함한 목록으로 통째로 교체한다(등록과 같은 규칙 — 좌표는 "확인"으로 채운다).
    """
    course = db.get(Course, course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    course.name = payload.name
    course.distance_km = payload.distance_km
    course.difficulty = payload.difficulty
    course.address = payload.address
    course.tags = payload.tags
    course.description = payload.description
    course.parkings = [facility.model_dump() for facility in payload.parkings]
    course.restrooms = [facility.model_dump() for facility in payload.restrooms]

    db.commit()
    db.refresh(course)

    counts = _completed_counts(db, [course.id])
    mine = _my_completed_course_ids(db, user_id, [course.id])

    return _to_summary(course, counts.get(course.id, 0), course.id in mine)


@router.post("/courses/gpx", response_model=CourseSummary, status_code=201)
def create_course_from_gpx(
    file: UploadFile = File(..., description="GPX 파일"),
    distance_km: int = Form(..., ge=1, description="왕복 기준 거리(km)"),
    difficulty: Difficulty = Form(..., description="1=★, 2=★★, 3=★★★"),
    address: str = Form(..., min_length=1, description="코스 시작 지점 주소"),
    name: str | None = Form(default=None, description="생략하면 GPX의 <name>을 쓴다"),
    tags: str | None = Form(default=None, description='쉼표로 구분 — "해안도로,제주시"'),
    parkings: str = Form(
        default="[]",
        description='주차장 목록 JSON. 각 원소 {name?, address, lat, lng} — 좌표는 "확인"으로 채운다',
    ),
    restrooms: str = Form(
        default="[]", description="화장실 목록 JSON. 형식은 parkings와 같다"
    ),
    description: str | None = Form(default=None),
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """GPX로 코스를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)

    거리·난이도·주소는 GPX에서 알 수 없으므로 폼으로 받는다. 특히 거리는 GPX를
    실측한 값이 아니라 코스 명단에 적힌 왕복 안내값이다.

    주차장/화장실은 좌표까지 포함한 JSON 목록으로 받는다. 좌표는 등록 화면의
    "확인"(GET /admin/geo/geocode)이 미리 채워 보낸다 — 여기서 다시 변환하지 않는다.
    """
    content = file.file.read(MAX_GPX_BYTES + 1)
    if len(content) > MAX_GPX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"GPX 파일이 너무 커요. {MAX_GPX_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )

    try:
        parsed_parkings = _facility_list.validate_json(parkings)
        parsed_restrooms = _facility_list.validate_json(restrooms)
    except ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail="주차장/화장실 형식이 올바르지 않아요(좌표가 빠졌을 수 있어요).",
        ) from exc

    try:
        course = create_course_from_gpx_bytes(
            db,
            content,
            name=name,
            distance_km=distance_km,
            difficulty=difficulty,
            address=address,
            tags=tags,
            parkings=[facility.model_dump() for facility in parsed_parkings],
            restrooms=[facility.model_dump() for facility in parsed_restrooms],
            description=description,
            created_by=user_id,
        )
    except CourseUploadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    # 방금 만든 코스라 완주자는 아직 없다.
    return _to_summary(course, 0, False)
