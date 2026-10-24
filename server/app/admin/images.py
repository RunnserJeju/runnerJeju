"""운영툴 이미지 업로드 공통 — 타입·용량 검사. 코스·협력업체 썸네일/추가 이미지가 같이 쓴다.

픽셀 크기·비율은 보지 않는다(이미지 디코딩 라이브러리 없음). 그건 운영 웹이 올리기 전에
막는다(components/imageSpec.ts).
"""

from fastapi import HTTPException, UploadFile

# 폰 원본 사진이 올라올 수 있어 넉넉히 둔다. 확장자는 Storage 오브젝트 경로로도 쓰인다.
MAX_IMAGE_BYTES = 8 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}

# 썸네일 말고 더 보여 줄 이미지 수 상한(코스·협력업체 공통).
MAX_EXTRA_IMAGES = 10


def read_image_or_raise(file: UploadFile) -> tuple[bytes, str]:
    """(바이트, 확장자). 허용 타입이 아니거나 비었으면 422, 너무 크면 413."""
    extension = ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")
    content = file.file.read(MAX_IMAGE_BYTES + 1)
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_IMAGE_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")
    return content, extension
