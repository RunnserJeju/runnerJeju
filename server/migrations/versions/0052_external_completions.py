"""러닝 기록 없이 인정된 코스 완주: external_completions

가민·순토 링크 인증과 운영자 수동 인정을 한 줄씩 남긴다. 러닝(runs)을 만들지 않는 완주라
verifications에 담을 수 없어 따로 둔다. 새 테이블이라 기존 데이터·코드에 영향이 없다.

Revision ID: 0052_external_completions
Revises: 0051_crash_reports
Create Date: 2026-11-15 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0052_external_completions"
down_revision: Union[str, Sequence[str], None] = "0051_crash_reports"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "external_completions",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.String(length=100), nullable=False),
        sa.Column("course_id", sa.UUID(), nullable=False),
        sa.Column("source", sa.String(length=20), nullable=False),
        sa.Column("activity_id", sa.String(length=100), nullable=True),
        sa.Column("url", sa.String(length=500), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("match_rate", sa.Float(), nullable=True),
        sa.Column("detail", sa.String(length=500), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("distance_meters", sa.Float(), nullable=True),
        sa.Column("point_count", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["course_id"], ["courses.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_external_completions_user_id", "external_completions", ["user_id"])
    op.create_index("ix_external_completions_course_id", "external_completions", ["course_id"])
    op.create_index(
        "uq_external_completion_activity",
        "external_completions",
        ["source", "activity_id"],
        unique=True,
        postgresql_where=sa.text("status = 'matched' AND activity_id IS NOT NULL"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("uq_external_completion_activity", table_name="external_completions")
    op.drop_index("ix_external_completions_course_id", table_name="external_completions")
    op.drop_index("ix_external_completions_user_id", table_name="external_completions")
    op.drop_table("external_completions")
