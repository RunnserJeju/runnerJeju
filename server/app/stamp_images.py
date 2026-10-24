"""코스 완주 스탬프의 기본 도안 — 코스 카테고리별 고정 파일.

stamp_definitions.image_url이 비어 있으면 그 코스의 category(art/road/trail/challenge)로
도안을 정한다. 파일은 Storage `course-stamps/category/{category}_run.png`에 고정 경로로 두고
(scripts/upload_category_stamps.py), DB에는 URL을 저장하지 않는다 — 코스 카테고리를 바꾸면
도안도 따라 바뀌고, 운영툴에서 도안을 올리면 그게 우선이다(지우면 다시 기본으로).
"""

import uuid
from collections.abc import Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import storage
from app.models import COURSE_CATEGORIES, Course, StampDefinition
from app.stamp_rules import COURSE_COMPLETE

CATEGORY_DIR = "category"


def category_object_path(category: str) -> str:
    """버킷 안 오브젝트 경로. 업로드 스크립트와 URL이 같은 규칙을 쓴다."""
    return f"{CATEGORY_DIR}/{category}_run.png"


def category_stamp_url(category: str | None) -> str | None:
    if not category or category not in COURSE_CATEGORIES or not storage.SUPABASE_URL:
        return None
    return (
        f"{storage.SUPABASE_URL}/storage/v1/object/public/"
        f"{storage.SUPABASE_STAMP_BUCKET}/{category_object_path(category)}"
    )


def resolve_image_url(definition: StampDefinition, category: str | None) -> str | None:
    """앱에 내려줄 도안. 직접 올린 도안 > 코스 카테고리 기본 > 없음(앱이 기본 원을 그림)."""
    if definition.image_url:
        return definition.image_url
    if definition.condition_type != COURSE_COMPLETE:
        return None
    return category_stamp_url(category)


def course_categories(db: Session, course_ids: Iterable[uuid.UUID]) -> dict[uuid.UUID, str]:
    ids = list(course_ids)
    if not ids:
        return {}
    rows = db.execute(select(Course.id, Course.category).where(Course.id.in_(ids))).all()
    return {course_id: category for course_id, category in rows}
