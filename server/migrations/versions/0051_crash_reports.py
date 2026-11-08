"""앱 크래시 리포트: crash_reports

앱이 다음 실행 때 올리는 크래시·ANR·iOS 멈춤 요약(POST /crash-reports). 원본 덤프는
비공개 Storage 버킷에 두고 경로만 남긴다. 새 테이블이라 기존 데이터·코드에 영향이 없다.

Revision ID: 0051_crash_reports
Revises: 0050_event_sort_order_renumber
Create Date: 2026-11-08 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0051_crash_reports"
down_revision: Union[str, Sequence[str], None] = "0050_event_sort_order_renumber"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "crash_reports",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.String(length=100), nullable=True),
        sa.Column("session_id", sa.String(length=36), nullable=True),
        sa.Column("platform", sa.String(length=10), nullable=True),
        sa.Column("app_version", sa.String(length=20), nullable=True),
        sa.Column("device", sa.String(length=100), nullable=True),
        sa.Column("os_version", sa.String(length=100), nullable=True),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("summary", sa.String(length=500), nullable=True),
        sa.Column("culprit", sa.String(length=200), nullable=True),
        sa.Column("stack", sa.Text(), nullable=True),
        sa.Column("dump_path", sa.String(length=200), nullable=True),
        sa.Column(
            "context",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crash_reports_occurred", "crash_reports", ["occurred_at"])
    op.create_index("ix_crash_reports_user_id", "crash_reports", ["user_id"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_crash_reports_user_id", table_name="crash_reports")
    op.drop_index("ix_crash_reports_occurred", table_name="crash_reports")
    op.drop_table("crash_reports")
