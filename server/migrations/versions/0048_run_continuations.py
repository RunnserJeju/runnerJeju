"""이어달리기: runs.continuations(붙인 구간 목록) + runs.updated_at

미완주 코스 러닝에 나중에 달린 구간을 이어 붙인다(POST /runs/{id}/continue).
기존 기록은 붙인 구간이 없으므로 빈 배열, updated_at은 NULL이다.

Revision ID: 0048_run_continuations
Revises: 0047_coupon_revoke_admin_actions
Create Date: 2026-11-08 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0048_run_continuations"
down_revision: Union[str, Sequence[str], None] = "0047_coupon_revoke_admin_actions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "runs",
        sa.Column(
            "continuations",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column(
        "runs", sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("runs", "updated_at")
    op.drop_column("runs", "continuations")
