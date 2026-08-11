"""배너 라우터(list_banners, create_banner, delete_banner) 테스트.

test_notices.py와 같은 방침으로 DB 없이 Session의 최소 인터페이스만 흉내내는
FakeSession을 쓴다. require_admin이 하는 권한 검사 자체는 라우터 함수를 직접
호출하면 우회되므로(Depends가 실행되지 않는다) test_deps.py의 TestRequireAdmin에서
따로 검증한다.

Supabase Storage 호출(app.storage.upload_image/delete_image)은 실제 네트워크를
타므로 매 테스트에서 monkeypatch로 갈아끼운다 — 이 파일은 라우터 로직만 본다.
"""

import io
import uuid

import pytest
from fastapi import HTTPException

from app import storage
from app.models import Banner
from app.routers import banners as banners_router


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class FakeSession:
    def __init__(self, banners: list[Banner] | None = None):
        self._banners = list(banners or [])
        self.added: list[object] = []
        self.deleted: list[object] = []

    def execute(self, _stmt):
        return _FakeResult(list(self._banners))

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)
        self._banners.append(obj)

    def get(self, _model, banner_id):
        return next((b for b in self._banners if b.id == banner_id), None)

    def delete(self, obj):
        self.deleted.append(obj)
        self._banners.remove(obj)

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


class FakeUploadFile:
    """FastAPI UploadFile 대신 라우터가 실제로 쓰는 두 속성만 흉내낸다."""

    def __init__(self, content: bytes, content_type: str = "image/jpeg"):
        self.content_type = content_type
        self.file = io.BytesIO(content)


class TestListBanners:
    def test_returns_existing_banners(self):
        existing = [
            Banner(id=uuid.uuid4(), image_url="https://x/a.jpg", sort_order=0),
            Banner(id=uuid.uuid4(), image_url="https://x/b.jpg", sort_order=1),
        ]
        db = FakeSession(banners=existing)

        result = banners_router.list_banners(db, user_id=str(uuid.uuid4()))

        assert result == existing

    def test_returns_empty_list_when_no_banners(self):
        db = FakeSession()

        result = banners_router.list_banners(db, user_id=str(uuid.uuid4()))

        assert result == []


class TestCreateBanner:
    def test_creates_banner_with_uploaded_image_url(self, monkeypatch):
        monkeypatch.setattr(
            storage, "upload_image", lambda content, **kw: "https://cdn/x.jpg"
        )
        db = FakeSession()
        file = FakeUploadFile(b"fake-image-bytes", content_type="image/png")

        result = banners_router.create_banner(
            file=file, sort_order=2, db=db, user_id=str(uuid.uuid4())
        )

        assert result.image_url == "https://cdn/x.jpg"
        assert result.sort_order == 2
        assert result in db.added

    def test_rejects_disallowed_content_type(self):
        db = FakeSession()
        file = FakeUploadFile(b"not-an-image", content_type="text/plain")

        with pytest.raises(HTTPException) as exc_info:
            banners_router.create_banner(
                file=file, sort_order=0, db=db, user_id=str(uuid.uuid4())
            )

        assert exc_info.value.status_code == 422

    def test_rejects_empty_file(self):
        db = FakeSession()
        file = FakeUploadFile(b"", content_type="image/jpeg")

        with pytest.raises(HTTPException) as exc_info:
            banners_router.create_banner(
                file=file, sort_order=0, db=db, user_id=str(uuid.uuid4())
            )

        assert exc_info.value.status_code == 422

    def test_rejects_oversized_file(self):
        db = FakeSession()
        oversized = b"x" * (banners_router.MAX_BANNER_IMAGE_BYTES + 1)
        file = FakeUploadFile(oversized, content_type="image/jpeg")

        with pytest.raises(HTTPException) as exc_info:
            banners_router.create_banner(
                file=file, sort_order=0, db=db, user_id=str(uuid.uuid4())
            )

        assert exc_info.value.status_code == 413

    def test_wraps_storage_upload_error_as_502(self, monkeypatch):
        def _raise(content, **kw):
            raise storage.StorageUploadError("업로드 설정이 안 되어 있어요.")

        monkeypatch.setattr(storage, "upload_image", _raise)
        db = FakeSession()
        file = FakeUploadFile(b"fake-image-bytes", content_type="image/jpeg")

        with pytest.raises(HTTPException) as exc_info:
            banners_router.create_banner(
                file=file, sort_order=0, db=db, user_id=str(uuid.uuid4())
            )

        assert exc_info.value.status_code == 502


class TestDeleteBanner:
    def test_deletes_existing_banner_and_its_storage_object(self, monkeypatch):
        deleted_urls = []
        monkeypatch.setattr(storage, "delete_image", deleted_urls.append)

        banner = Banner(id=uuid.uuid4(), image_url="https://cdn/x.jpg", sort_order=0)
        db = FakeSession(banners=[banner])

        banners_router.delete_banner(
            banner_id=banner.id, db=db, user_id=str(uuid.uuid4())
        )

        assert banner in db.deleted
        assert deleted_urls == ["https://cdn/x.jpg"]

    def test_raises_404_when_banner_not_found(self):
        db = FakeSession()

        with pytest.raises(HTTPException) as exc_info:
            banners_router.delete_banner(
                banner_id=uuid.uuid4(), db=db, user_id=str(uuid.uuid4())
            )

        assert exc_info.value.status_code == 404
