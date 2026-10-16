"""앱 홈 구성 테이블 추가 — course_curations, partner_curations

앱 홈의 '러닝 코스 큐레이션'(코스)과 '추천 협력 업체'(업체)에 무엇을 어떤 순서로
띄울지 운영 웹 '홈 구성' 화면에서 고른다. 홈에 나오는 건 섹션마다 몇 개뿐이라
courses/partners에 대부분 비어 있을 컬럼을 붙이지 않고, 고른 것만 행으로 담는다.

- course_curations: course_id PK + 표시 순서. 코스가 지워지면 CASCADE로 빠진다.
- partner_curations: partner_id PK + 표시 순서. 업체가 지워지면 CASCADE로 빠진다.

새 테이블만 만들므로 옛 코드에 무해하다. 적용 직후에는 두 테이블이 비어 있어 홈
두 섹션이 접혀 있다가, 운영자가 '홈 구성'에서 고르면 채워진다.

Revision ID: 0029_home_curations
Revises: 0028_course_original_gpx
Create Date: 2026-10-17 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0029_home_curations"
down_revision: Union[str, Sequence[str], None] = "0028_course_original_gpx"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "course_curations",
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_table(
        "partner_curations",
        sa.Column(
            "partner_id",
            UUID(as_uuid=True),
            sa.ForeignKey("partners.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("partner_curations")
    op.drop_table("course_curations")
