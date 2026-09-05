"""course_views 테이블 생성 (코스별 조회수)

코스 상세(GET /courses/{id}) 조회를 하루 1회 중복제거로 기록한다 —
(course_id, user_id, view_date) 유니크라 같은 사람이 하루에 같은 코스를 여러 번 열어도
행은 하나다. 그래서 조회수는 raw 클릭 수가 아니라 '고유 조회(사람·일 단위)'다.
GET /courses/{id}가 ON CONFLICT DO NOTHING으로 기록한다.

Revision ID: 0020_course_views
Revises: 0019_user_withdrawal
Create Date: 2026-09-06 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0020_course_views"
down_revision: Union[str, Sequence[str], None] = "0019_user_withdrawal"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "course_views",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("course_id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column("view_date", sa.Date(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["course_id"], ["courses.id"]),
        sa.UniqueConstraint(
            "course_id", "user_id", "view_date", name="uq_course_view_user_day"
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("course_views")
