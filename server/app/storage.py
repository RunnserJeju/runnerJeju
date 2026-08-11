"""Supabase Storage 업로드.

배너 이미지처럼 관리자가 앱에서 올리는 파일을 Supabase Storage에 저장한다.
서버가 `service_role` 키로 REST API를 직접 호출해서 대신 올린다 — 앱이 Storage에
직접 쓰게 하려면 Supabase Auth로 RLS(업로드 권한) 정책을 걸어야 하는데, 이
프로젝트는 자체 JWT로 로그인/권한을 관리해서(app.deps.require_admin) 인증
체계가 두 벌로 갈라진다. 백엔드가 대신 올리면 기존 관리자 체크 하나로 충분하고,
`service_role` 키가 모든 정책을 무시하니 Storage 쪽엔 별도 쓰기 정책이 필요 없다
(읽기는 버킷을 Public으로 만들어 해결한다).
"""

import os
import uuid

import httpx

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
SUPABASE_STORAGE_BUCKET = os.environ.get("SUPABASE_STORAGE_BUCKET", "banners")


class StorageUploadError(RuntimeError):
    """설정 누락이나 업로드 실패. message는 그대로 사용자에게 보여줘도 된다."""


def upload_image(content: bytes, *, content_type: str, extension: str) -> str:
    """이미지 바이트를 Storage에 올리고 public URL을 돌려준다.

    오브젝트 경로는 매번 uuid4로 새로 만든다 — 같은 배너를 다시 올려도 옛 URL을
    가리키는 캐시(CDN·클라이언트 이미지 캐시)가 새 이미지를 안 보여주는 문제를
    피하려고. 옛 오브젝트를 지우는 로직은 아직 없다(배너 개수가 적어서 나중에
    정리해도 됨 — 1GB 프리 티어 기준 참고).
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise StorageUploadError(
            "이미지 업로드가 설정되어 있지 않아요 (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)."
        )

    path = f"{uuid.uuid4()}.{extension}"

    response = httpx.put(
        f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_STORAGE_BUCKET}/{path}",
        headers={
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Content-Type": content_type,
        },
        content=content,
        timeout=30,
    )

    if response.status_code >= 400:
        raise StorageUploadError(f"이미지 업로드에 실패했어요: {response.text[:200]}")

    return f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_STORAGE_BUCKET}/{path}"


def delete_image(image_url: str) -> None:
    """`upload_image`가 돌려준 public URL로 Storage 오브젝트를 지운다.

    실패해도 예외를 던지지 않는다 — 호출자(배너 삭제)는 DB row를 지우는 게
    본목적이고, Storage 정리는 부가적이다. URL 형식이 예상과 달라 경로를 못
    뽑거나 이미 지워진 파일이면 조용히 넘어간다.
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        return

    marker = f"/object/public/{SUPABASE_STORAGE_BUCKET}/"
    if marker not in image_url:
        return
    path = image_url.split(marker, 1)[1]

    try:
        httpx.delete(
            f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_STORAGE_BUCKET}/{path}",
            headers={
                "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
                "apikey": SUPABASE_SERVICE_ROLE_KEY,
            },
            timeout=30,
        )
    except httpx.HTTPError:
        pass
