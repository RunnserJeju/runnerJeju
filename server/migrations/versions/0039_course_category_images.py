"""코스 카테고리(courses.category, 필수) + 추가 이미지(courses.image_urls)

- category: 'art'(아트런) | 'road'(로드런) | 'trail'(트레일런) | 'challenge'(챌린지런).
  기존 코스는 태그로 채운다 — '아트런' → art, '트레일러닝' → trail, 나머지 road.
  채운 뒤 NOT NULL + CHECK.
- image_urls: 썸네일 말고 더 보여 줄 이미지 URL 목록(순서대로). 기본 빈 목록.

Revision ID: 0039_course_category_images
Revises: 0038_running_week_round
Create Date: 2026-10-22 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0039_course_category_images"
down_revision: Union[str, Sequence[str], None] = "0038_running_week_round"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("courses", sa.Column("category", sa.String(20), nullable=True))
    op.execute(
        """
        UPDATE courses SET category = CASE
          WHEN tags LIKE '%아트런%' THEN 'art'
          WHEN tags LIKE '%트레일러닝%' THEN 'trail'
          ELSE 'road'
        END
        """
    )
    op.alter_column("courses", "category", nullable=False)
    op.create_check_constraint(
        "ck_courses_category", "courses", "category IN ('art', 'road', 'trail', 'challenge')"
    )

    op.add_column(
        "courses",
        sa.Column("image_urls", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("courses", "image_urls")
    op.drop_constraint("ck_courses_category", "courses", type_="check")
    op.drop_column("courses", "category")
