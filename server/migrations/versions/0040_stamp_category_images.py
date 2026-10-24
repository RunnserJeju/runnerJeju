"""코스 완주 스탬프 도안을 코스 카테고리 기본으로 — 난이도별 도안 URL 비우기

코스 완주 스탬프의 도안은 이제 image_url이 비어 있으면 코스 category별 고정 파일을
쓴다(app/stamp_images.py). 예전에 난이도(basic/intermediate/advanced)별로 넣어 둔 URL은
카테고리 기본이 적용되도록 비운다. 운영툴에서 따로 올린 도안(uuid 파일명)은 그대로 둔다.

Revision ID: 0040_stamp_category_images
Revises: 0039_course_category_images
Create Date: 2026-10-22 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0040_stamp_category_images"
down_revision: Union[str, Sequence[str], None] = "0039_course_category_images"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute(
        """
        UPDATE stamp_definitions SET image_url = NULL
        WHERE condition_type = 'course_complete'
          AND image_url LIKE '%/course-stamps/difficulty/%'
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    # 비운 난이도 URL은 되돌릴 근거가 없다. 카테고리 기본이 계속 쓰인다.
