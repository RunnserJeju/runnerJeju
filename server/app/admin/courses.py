"""운영자 전용 코스 API — 등록/수정. 공개 조회는 app.routers.courses에 있다.

응답 변환·완주자 조회·GPX 파싱 등 공유 로직은 app.routers.courses가 소유하고
(tools/push_courses.py도 그 진입점을 쓴다) 여기서는 import해 재사용한다.
"""

import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import TypeAdapter, ValidationError
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import Course, Run, Stamp, Verification
from app.routers.courses import (
    CourseUploadError,
    _completed_counts,
    _to_summary,
    create_course_from_gpx_bytes,
    resample_path_from_gpx,
)
from app.schemas import CourseListItem, CourseSummary, CourseUpdate, Difficulty, Facility

router = APIRouter(tags=["courses"])

# 업로드 가능한 GPX 최대 크기. 6.2km 코스가 36KB이므로 넉넉하다.
# 제한이 없으면 거대한 파일 하나로 워커 메모리를 채울 수 있다.
MAX_GPX_BYTES = 5 * 1024 * 1024

# 썸네일 이미지 제한. 배너(admin/banners.py)와 같은 규칙 — 폰 원본 사진이
# 올라올 수 있어 넉넉히 두고, 확장자는 Storage 오브젝트 경로로도 쓰인다.
MAX_THUMBNAIL_BYTES = 8 * 1024 * 1024
_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}

# 멀티파트 폼에 파일과 함께 실려오는 parkings/restrooms를 검증한다. 폼 필드라
# JSON 문자열로 오므로 validate_json으로 파싱한다(각 원소는 Facility = 좌표 포함).
_facility_list = TypeAdapter(list[Facility])


# 운영 웹용 목록/상세. 공개 GET /courses는 앱 로그인(JWT)이 필요해
# (is_completed_by_me 계산) 운영 웹이 쓸 수 없다 — API 키로 접근하는 사본을 둔다.
# is_completed_by_me는 운영자에겐 무의미하므로 False 고정.
@router.get("/courses", response_model=list[CourseListItem])
def list_courses(db: Session = Depends(get_db)):
    """전체 코스 목록. (관리자 전용 — 라우터 레벨에서 강제)"""
    courses = db.execute(select(Course).order_by(Course.created_at.desc())).scalars().all()
    counts = _completed_counts(db, [course.id for course in courses])
    return [_to_summary(course, counts.get(course.id, 0), False) for course in courses]


@router.get("/courses/{course_id}", response_model=CourseSummary)
def get_course(course_id: uuid.UUID, db: Session = Depends(get_db)):
    """코스 상세(경로 포함). (관리자 전용 — 라우터 레벨에서 강제)"""
    course = _load_course_or_404(db, course_id)
    counts = _completed_counts(db, [course.id])
    return _to_summary(course, counts.get(course.id, 0), False)


@router.patch("/courses/{course_id}", response_model=CourseSummary)
def update_course(
    course_id: uuid.UUID,
    payload: CourseUpdate,
    db: Session = Depends(get_db),
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
    course.estimated_time_min = payload.estimated_time_min
    course.parkings = [facility.model_dump() for facility in payload.parkings]
    course.restrooms = [facility.model_dump() for facility in payload.restrooms]

    db.commit()
    db.refresh(course)

    counts = _completed_counts(db, [course.id])

    # is_completed_by_me는 앱 사용자 기준 값이라 운영자에겐 의미가 없다 — False 고정.
    return _to_summary(course, counts.get(course.id, 0), False)


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
    estimated_time_min: int | None = Form(
        default=None, ge=1, description="예상 소요시간(분). 안내값 — 생략 가능"
    ),
    db: Session = Depends(get_db),
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
            estimated_time_min=estimated_time_min,
            # API 키 인증이라 개인 식별자가 없다. 세션 인증이 오면 운영자 id로 바꾼다.
            created_by="admin-web",
        )
    except CourseUploadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    # 방금 만든 코스라 완주자는 아직 없다. 썸네일은 아직 없다 — 등록 직후
    # PUT /courses/{id}/thumbnail으로 따로 올린다.
    return _to_summary(course, 0, False)


def _load_course_or_404(db: Session, course_id: uuid.UUID) -> Course:
    course = db.get(Course, course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")
    return course


def _course_has_activity(db: Session, course_id: uuid.UUID) -> bool:
    """이 코스로 달리거나(러닝) 검증·완주한 기록이 하나라도 있으면 True.

    경로 교체 시 확인을 강제하는 가드용이다. 찜(Favorite)은 경로와 무관하니 세지
    않는다 — 찜만 된 코스는 경로를 바꿔도 기존 데이터가 어긋날 게 없다.
    """
    for model in (Run, Stamp, Verification):
        row = db.execute(
            select(model.id).where(model.course_id == course_id).limit(1)
        ).first()
        if row is not None:
            return True
    return False


def _reset_course_records(db: Session, course_id: uuid.UUID) -> None:
    """이 코스의 완주 스탬프와 검증을 모두 지운다(hard delete).

    경로가 바뀌면 옛 경로 기준으로 계산된 완주·검증은 새 경로와 어긋나므로
    초기화한다. **개인 러닝 기록(Run)은 남긴다** — "언제 얼마 달렸다"는 개인 활동
    히스토리이고, 원본 GPS·시각이 남아 이 초기화의 감사 흔적 역할도 한다.
    (Run에 course_id는 남지만 완주 여부는 Stamp가 정하므로, "달렸지만 완주 스탬프는
    없음"이라는 정상 상태가 된다.)

    커밋은 호출한 엔드포인트가 경로 교체까지 묶어 한 트랜잭션으로 처리한다.
    """
    db.execute(delete(Verification).where(Verification.course_id == course_id))
    db.execute(delete(Stamp).where(Stamp.course_id == course_id))


@router.put("/courses/{course_id}/gpx", response_model=CourseSummary)
def replace_course_gpx(
    course_id: uuid.UUID,
    file: UploadFile = File(..., description="새 GPX 파일"),
    reset_records: bool = Form(
        default=False,
        description="이 코스로 달린 기록이 있으면 True로 보내야 진행됨. "
        "완주 스탬프·검증이 초기화된다(개인 러닝 기록은 유지).",
    ),
    db: Session = Depends(get_db),
):
    """코스의 경로(path)를 새 GPX로 교체한다. (관리자 전용 — 라우터 레벨에서 강제)

    이 코스로 달린 기록(러닝·검증·완주 스탬프)이 있으면, 경로를 바꾸는 순간 그
    기록들의 완주·진행률 판정 기준이 옛 경로로 계산돼 새 경로와 어긋난다. 그래서:

    - 기록이 있는데 `reset_records`가 False면 **409**로 막는다 — 클라이언트가
      "완주 기록이 초기화됩니다" 경고를 띄우고 확인받으라는 신호다.
    - `reset_records=True`면 완주 스탬프·검증을 초기화(hard delete)한 뒤 경로를
      교체한다. 개인 러닝 기록(Run)은 남긴다(_reset_course_records 참고).
    - 기록이 없으면 플래그와 무관하게 그냥 교체한다.

    메타데이터·썸네일은 건드리지 않는다 — 경로만 리샘플해 갈아끼운다. 파일 검증을
    먼저 끝낸 뒤에 초기화하므로, GPX가 잘못됐으면 아무것도 지우지 않고 422로 멈춘다.
    """
    course = _load_course_or_404(db, course_id)

    has_activity = _course_has_activity(db, course_id)
    if has_activity and not reset_records:
        raise HTTPException(
            status_code=409,
            detail="이 코스로 달린 기록이 있어요. 경로를 바꾸면 완주 기록이 초기화돼요. "
            "확인하면 reset_records=true로 다시 요청해 주세요.",
        )

    content = file.file.read(MAX_GPX_BYTES + 1)
    if len(content) > MAX_GPX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"GPX 파일이 너무 커요. {MAX_GPX_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )

    # 파일을 먼저 검증한다 — 초기화(삭제)보다 앞에 둬서, 잘못된 GPX면 기록을
    # 지우지 않고 멈추게 한다.
    try:
        new_path = resample_path_from_gpx(content)
    except CourseUploadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    if has_activity:
        _reset_course_records(db, course_id)

    course.path = new_path
    db.commit()
    db.refresh(course)

    counts = _completed_counts(db, [course.id])
    return _to_summary(course, counts.get(course.id, 0), False)


@router.put("/courses/{course_id}/thumbnail", response_model=CourseSummary)
def set_course_thumbnail(
    course_id: uuid.UUID,
    file: UploadFile = File(..., description="썸네일 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """코스 대표 썸네일을 올린다(교체 포함). (관리자 전용 — 라우터 레벨에서 강제)

    이미지 자체를 하나의 리소스로 다뤄 등록/수정 폼과 분리했다 — 파일 처리·교체·
    삭제 로직이 여기 한 곳에 모인다(배너와 같은 방침). 등록도 이 엔드포인트로
    올리므로 "처음 설정"과 "교체"가 같은 코드를 탄다.

    교체면 옛 오브젝트는 새로 올린 뒤 지운다 — Storage는 매번 새 경로에 저장해
    (app.storage) 옛 파일이 고아로 남기 때문이다. 삭제 실패는 무시한다(부가 작업).
    """
    course = _load_course_or_404(db, course_id)

    extension = _ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")

    content = file.file.read(MAX_THUMBNAIL_BYTES + 1)
    if len(content) > MAX_THUMBNAIL_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_THUMBNAIL_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")

    try:
        new_url = storage.upload_image(
            content,
            content_type=file.content_type,
            extension=extension,
            bucket=storage.SUPABASE_COURSE_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    # 업로드가 성공한 뒤에야 옛 것을 지운다 — 실패하면 옛 썸네일이 그대로 살아 있게.
    old_url = course.thumbnail_url
    course.thumbnail_url = new_url
    db.commit()
    db.refresh(course)

    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_COURSE_BUCKET)

    counts = _completed_counts(db, [course.id])
    return _to_summary(course, counts.get(course.id, 0), False)


@router.delete("/courses/{course_id}/thumbnail", response_model=CourseSummary)
def delete_course_thumbnail(
    course_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    """코스 썸네일을 지운다(컬럼을 NULL로). (관리자 전용 — 라우터 레벨에서 강제)

    이미 없으면 아무 일도 안 한다. Storage 파일도 지우되 실패는 무시한다.
    """
    course = _load_course_or_404(db, course_id)

    old_url = course.thumbnail_url
    if old_url:
        course.thumbnail_url = None
        db.commit()
        db.refresh(course)
        storage.delete_image(old_url, bucket=storage.SUPABASE_COURSE_BUCKET)

    counts = _completed_counts(db, [course.id])
    return _to_summary(course, counts.get(course.id, 0), False)
