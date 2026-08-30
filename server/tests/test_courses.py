"""코스 등록(create_course_from_gpx_bytes)과 응답 변환(_to_summary) 테스트.

주차장/화장실(parkings/restrooms) JSONB로 넘어가면서 바뀐 부분을 본다:
  - create_course_from_gpx_bytes가 좌표 포함 dict 목록을 그대로 저장하는지
  - _to_summary가 응답에 목록을 담는지
  - Facility 스키마가 좌표 없는 입력을 거르는지(=등록 화면 "확인"을 강제)
  - push_courses가 명단 주소를 geocode해 좌표를 채우는지

DB 없이 라우터 함수를 직접 부르고 Session은 FakeSession으로 흉내낸다
(test_banners.py와 같은 방침). GPX는 실제 코스 파일(sagye-coastal.gpx)을 쓴다.
"""

import io
import uuid
from pathlib import Path

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import geocoding, storage
from app.admin import courses as admin_courses_router
from app.models import Course
from app.routers import courses as courses_router
from app.schemas import CourseUpdate, Facility
from tools import push_courses

SAGYE = Path(__file__).resolve().parent.parent / "courses" / "sagye-coastal.gpx"

PARKING = {"name": "송악산 주차장", "address": "제주 대정읍 상모리 4165", "lat": 33.21, "lng": 126.29}
RESTROOM = {"name": None, "address": "제주 대정읍 송악관광로 40", "lat": 33.22, "lng": 126.28}


class FakeSession:
    def __init__(self):
        self.added: list[object] = []

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


def _create(db, **overrides) -> Course:
    kwargs = dict(
        name="테스트 코스",
        distance_km=6,
        difficulty=2,
        address="제주시 어딘가",
        tags=None,
        parkings=[],
        restrooms=[],
        description=None,
        created_by="tester",
    )
    kwargs.update(overrides)
    return courses_router.create_course_from_gpx_bytes(db, SAGYE.read_bytes(), **kwargs)


class TestCreateCourseFacilities:
    def test_stores_parkings_and_restrooms(self):
        db = FakeSession()
        course = _create(db, parkings=[PARKING], restrooms=[RESTROOM])

        assert course.parkings == [PARKING]
        assert course.restrooms == [RESTROOM]

    def test_defaults_to_empty_lists(self):
        # 주차장/화장실을 안 넘기면 빈 리스트다(옛 코드처럼 None이 아니라).
        db = FakeSession()
        course = courses_router.create_course_from_gpx_bytes(
            db,
            SAGYE.read_bytes(),
            name="c",
            distance_km=6,
            difficulty=2,
            address="제주",
            tags=None,
            description=None,
            created_by="t",
        )

        assert course.parkings == []
        assert course.restrooms == []

    def test_multiple_facilities_of_same_kind(self):
        db = FakeSession()
        rest2 = {"name": None, "address": "제주 다른곳", "lat": 33.3, "lng": 126.3}
        course = _create(db, restrooms=[RESTROOM, rest2])

        assert len(course.restrooms) == 2


class TestCreateCourseEstimatedTime:
    def test_stores_estimated_time_min(self):
        db = FakeSession()
        course = _create(db, estimated_time_min=90)

        assert course.estimated_time_min == 90

    def test_defaults_to_none(self):
        # 안 넘기면 None이다(명단에 소요시간이 없는 코스가 있다).
        db = FakeSession()
        course = _create(db)

        assert course.estimated_time_min is None

    def test_never_sets_thumbnail(self):
        # 썸네일은 등록에서 안 채운다 — 전용 엔드포인트가 따로 올린다.
        db = FakeSession()
        course = _create(db, estimated_time_min=60)

        assert course.thumbnail_url is None


class TestToSummary:
    def test_includes_facility_lists(self):
        course = Course(
            id=uuid.uuid4(),
            name="c",
            distance_km=6,
            difficulty=2,
            address="제주",
            path=[{"lat": 33.5, "lng": 126.5}],
            parkings=[PARKING],
            restrooms=[],
            estimated_time_min=75,
            thumbnail_url="https://example.com/a.png",
        )

        summary = courses_router._to_summary(course, 0, False)

        assert summary["parkings"] == [PARKING]
        assert summary["restrooms"] == []
        assert summary["estimated_time_min"] == 75
        assert summary["thumbnail_url"] == "https://example.com/a.png"

    def test_estimated_time_and_thumbnail_default_none(self):
        course = Course(
            id=uuid.uuid4(),
            name="c",
            distance_km=6,
            difficulty=2,
            address="제주",
            path=[],
            parkings=[],
            restrooms=[],
        )

        summary = courses_router._to_summary(course, 0, False)

        assert summary["estimated_time_min"] is None
        assert summary["thumbnail_url"] is None

    def test_empty_when_columns_are_none(self):
        # JSONB 기본값이 아직 안 붙은 옛 행 등에서 None이 와도 빈 리스트로 내려간다.
        course = Course(
            id=uuid.uuid4(),
            name="c",
            distance_km=6,
            difficulty=2,
            address="제주",
            path=[],
            parkings=None,
            restrooms=None,
        )

        summary = courses_router._to_summary(course, 0, False)

        assert summary["parkings"] == []
        assert summary["restrooms"] == []


class TestFacilitySchema:
    def test_rejects_missing_coordinates(self):
        # 좌표 없이 주소만 오면 거른다 — 등록 화면 "확인"을 강제하는 계약.
        with pytest.raises(ValidationError):
            Facility(name="x", address="제주 어딘가")

    def test_rejects_blank_address(self):
        with pytest.raises(ValidationError):
            Facility(address="", lat=33.5, lng=126.5)

    def test_accepts_full_entry_with_optional_name(self):
        facility = Facility(address="제주 A", lat=33.5, lng=126.5)

        assert facility.name is None
        assert (facility.lat, facility.lng) == (33.5, 126.5)


class _EmptyResult:
    """완주자 수/내 완주 조회가 비어 있는 것으로 흉내낸다(수정 로직만 볼 것이므로)."""

    def all(self):
        return []

    def scalars(self):
        return []


class UpdateFakeSession:
    def __init__(self, course: Course | None):
        self._course = course
        self.committed = False

    def get(self, _model, course_id):
        if self._course is not None and self._course.id == course_id:
            return self._course
        return None

    def execute(self, _stmt):
        return _EmptyResult()

    def commit(self):
        self.committed = True

    def refresh(self, _obj):
        pass


def _course(**overrides) -> Course:
    fields = dict(
        id=uuid.uuid4(),
        name="옛 이름",
        distance_km=6,
        difficulty=2,
        address="옛 주소",
        tags="옛,태그",
        description="옛 설명",
        path=[{"lat": 33.5, "lng": 126.5}, {"lat": 33.6, "lng": 126.6}],
        parkings=[],
        restrooms=[],
    )
    fields.update(overrides)
    return Course(**fields)


class TestUpdateCourse:
    def _payload(self, **overrides) -> CourseUpdate:
        fields = dict(
            name="새 이름",
            distance_km=9,
            difficulty=3,
            address="새 주소",
            tags="새,태그",
            description="새 설명",
            estimated_time_min=120,
            parkings=[PARKING],
            restrooms=[],
        )
        fields.update(overrides)
        return CourseUpdate(**fields)

    def test_updates_metadata_fields(self):
        course = _course()
        db = UpdateFakeSession(course)

        result = admin_courses_router.update_course(course.id, self._payload(), db, "admin")

        assert course.name == "새 이름"
        assert course.distance_km == 9
        assert course.difficulty == 3
        assert course.address == "새 주소"
        assert course.tags == "새,태그"
        assert course.description == "새 설명"
        assert course.estimated_time_min == 120
        assert db.committed is True
        # 응답에도 반영된다.
        assert result["name"] == "새 이름"
        assert result["estimated_time_min"] == 120

    def test_clears_estimated_time_with_none(self):
        # null을 보내면 소요시간을 지운다.
        course = _course(estimated_time_min=90)
        db = UpdateFakeSession(course)

        admin_courses_router.update_course(
            course.id, self._payload(estimated_time_min=None), db, "admin"
        )

        assert course.estimated_time_min is None

    def test_does_not_touch_thumbnail(self):
        # 메타데이터 수정은 썸네일을 건드리지 않는다(전용 엔드포인트 담당).
        course = _course(thumbnail_url="https://example.com/keep.png")
        db = UpdateFakeSession(course)

        admin_courses_router.update_course(course.id, self._payload(), db, "admin")

        assert course.thumbnail_url == "https://example.com/keep.png"

    def test_replaces_facilities(self):
        course = _course(parkings=[{"name": "옛주차장", "address": "옛", "lat": 1, "lng": 2}])
        db = UpdateFakeSession(course)

        admin_courses_router.update_course(
            course.id, self._payload(parkings=[PARKING], restrooms=[RESTROOM]), db, "admin"
        )

        assert course.parkings == [PARKING]
        assert course.restrooms == [RESTROOM]

    def test_does_not_touch_path(self):
        course = _course()
        original_path = list(course.path)
        db = UpdateFakeSession(course)

        admin_courses_router.update_course(course.id, self._payload(), db, "admin")

        assert course.path == original_path

    def test_404_when_course_missing(self):
        db = UpdateFakeSession(None)

        with pytest.raises(HTTPException) as exc_info:
            admin_courses_router.update_course(uuid.uuid4(), self._payload(), db, "admin")

        assert exc_info.value.status_code == 404
        assert db.committed is False


class TestCourseUpdateSchema:
    def test_rejects_zero_distance(self):
        with pytest.raises(ValidationError):
            CourseUpdate(name="x", distance_km=0, difficulty=2, address="제주")

    def test_rejects_out_of_range_difficulty(self):
        with pytest.raises(ValidationError):
            CourseUpdate(name="x", distance_km=5, difficulty=4, address="제주")

    def test_facilities_default_to_empty(self):
        payload = CourseUpdate(name="x", distance_km=5, difficulty=2, address="제주")

        assert payload.parkings == []
        assert payload.restrooms == []

    def test_estimated_time_defaults_to_none(self):
        payload = CourseUpdate(name="x", distance_km=5, difficulty=2, address="제주")

        assert payload.estimated_time_min is None

    def test_rejects_non_positive_estimated_time(self):
        with pytest.raises(ValidationError):
            CourseUpdate(
                name="x", distance_km=5, difficulty=2, address="제주", estimated_time_min=0
            )


class TestPushCoursesResolveFacilities:
    def _fake_geocode(self, lat=33.5, lng=126.5):
        return lambda address: [
            geocoding.GeocodeResult(address=address, road_address=None, lat=lat, lng=lng)
        ]

    def test_geocodes_each_address(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", self._fake_geocode(33.21, 126.29))

        resolved = push_courses._resolve_facilities(
            [{"name": "주차장A", "address": "제주 대정읍 상모리 4165"}], "주차장", "코스"
        )

        assert resolved == [
            {"name": "주차장A", "address": "제주 대정읍 상모리 4165", "lat": 33.21, "lng": 126.29}
        ]

    def test_none_specs_returns_empty(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", self._fake_geocode())

        assert push_courses._resolve_facilities(None, "주차장", "코스") == []

    def test_raises_when_address_not_found(self, monkeypatch):
        # 빈 결과 = 주소가 틀림. 좌표를 만들 수 없으니 명단을 고치라고 멈춘다.
        monkeypatch.setattr(geocoding, "geocode", lambda address: [])

        with pytest.raises(SystemExit, match="변환하지 못했"):
            push_courses._resolve_facilities([{"address": "없는주소 zzz"}], "주차장", "코스")

    def test_raises_when_address_missing(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", self._fake_geocode())

        with pytest.raises(SystemExit, match="address가 없어요"):
            push_courses._resolve_facilities([{"name": "이름만"}], "주차장", "코스")


class FakeUpload:
    """UploadFile 흉내 — content_type과 .file.read(n)만 있으면 엔드포인트가 돈다."""

    def __init__(self, content: bytes = b"img-bytes", content_type: str = "image/png"):
        self.content_type = content_type
        self.file = io.BytesIO(content)


class TestCourseThumbnail:
    def _patch_storage(self, monkeypatch, *, url="https://cdn/new.png"):
        """storage 업로드/삭제를 가로채 호출을 기록한다(네트워크 없이 로직만 본다)."""
        deleted: list[str] = []
        monkeypatch.setattr(
            storage,
            "upload_image",
            lambda content, *, content_type, extension, bucket=None: url,
        )
        monkeypatch.setattr(
            storage, "delete_image", lambda old, *, bucket=None: deleted.append(old)
        )
        return deleted

    def test_sets_thumbnail_when_none(self, monkeypatch):
        deleted = self._patch_storage(monkeypatch, url="https://cdn/new.png")
        course = _course(thumbnail_url=None)
        db = UpdateFakeSession(course)

        result = admin_courses_router.set_course_thumbnail(
            course.id, FakeUpload(), db, "admin"
        )

        assert course.thumbnail_url == "https://cdn/new.png"
        assert result["thumbnail_url"] == "https://cdn/new.png"
        # 옛 썸네일이 없었으니 삭제는 부르지 않는다.
        assert deleted == []

    def test_replaces_and_deletes_old(self, monkeypatch):
        deleted = self._patch_storage(monkeypatch, url="https://cdn/new.png")
        course = _course(thumbnail_url="https://cdn/old.png")
        db = UpdateFakeSession(course)

        admin_courses_router.set_course_thumbnail(course.id, FakeUpload(), db, "admin")

        assert course.thumbnail_url == "https://cdn/new.png"
        # 교체 시 옛 오브젝트를 지운다.
        assert deleted == ["https://cdn/old.png"]

    def test_rejects_non_image_type(self, monkeypatch):
        self._patch_storage(monkeypatch)
        course = _course(thumbnail_url=None)
        db = UpdateFakeSession(course)

        with pytest.raises(HTTPException) as exc_info:
            admin_courses_router.set_course_thumbnail(
                course.id, FakeUpload(content_type="application/pdf"), db, "admin"
            )

        assert exc_info.value.status_code == 422
        assert course.thumbnail_url is None

    def test_set_404_when_course_missing(self, monkeypatch):
        self._patch_storage(monkeypatch)
        db = UpdateFakeSession(None)

        with pytest.raises(HTTPException) as exc_info:
            admin_courses_router.set_course_thumbnail(
                uuid.uuid4(), FakeUpload(), db, "admin"
            )

        assert exc_info.value.status_code == 404

    def test_delete_clears_and_removes_object(self, monkeypatch):
        deleted = self._patch_storage(monkeypatch)
        course = _course(thumbnail_url="https://cdn/old.png")
        db = UpdateFakeSession(course)

        result = admin_courses_router.delete_course_thumbnail(course.id, db, "admin")

        assert course.thumbnail_url is None
        assert result["thumbnail_url"] is None
        assert deleted == ["https://cdn/old.png"]

    def test_delete_is_noop_when_already_none(self, monkeypatch):
        deleted = self._patch_storage(monkeypatch)
        course = _course(thumbnail_url=None)
        db = UpdateFakeSession(course)

        admin_courses_router.delete_course_thumbnail(course.id, db, "admin")

        # 지울 게 없으면 Storage 삭제도 부르지 않는다.
        assert deleted == []

    def test_delete_404_when_course_missing(self, monkeypatch):
        self._patch_storage(monkeypatch)
        db = UpdateFakeSession(None)

        with pytest.raises(HTTPException) as exc_info:
            admin_courses_router.delete_course_thumbnail(uuid.uuid4(), db, "admin")

        assert exc_info.value.status_code == 404
