"""app_settings — 앱 원격 설정(키·값)

Revision ID: 0056_app_settings
Revises: 0055_user_log_user_time
Create Date: 2026-11-28 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0056_app_settings"
down_revision: Union[str, Sequence[str], None] = "0055_user_log_user_time"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "app_settings",
        sa.Column("key", sa.String(length=100), primary_key=True),
        sa.Column("value", postgresql.JSONB(), nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("app_settings")
