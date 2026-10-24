"""러닝위크·이벤트 공개 범위 — running_weeks.visibility, events.visibility

코스(visibility)와 같은 'public' | 'admin'. admin이면 role='admin'인 앱 사용자에게만
내려간다. 기존 행은 admin으로 둔다 — 출시 때 운영자만 먼저 보고, 운영툴에서 공개로 바꾼다.

Revision ID: 0042_rw_event_visibility
Revises: 0041_partner_images
Create Date: 2026-10-24 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0042_rw_event_visibility"
down_revision: Union[str, Sequence[str], None] = "0041_partner_images"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    for table in ("running_weeks", "events"):
        op.add_column(
            table,
            sa.Column("visibility", sa.String(20), nullable=False, server_default="admin"),
        )


def downgrade() -> None:
    """Downgrade schema."""
    for table in ("running_weeks", "events"):
        op.drop_column(table, "visibility")
