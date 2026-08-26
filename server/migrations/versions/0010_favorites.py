"""favorites

Revision ID: 0010_favorites
Revises: 0009_course_facilities_jsonb
Create Date: 2026-08-26 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0010_favorites"
down_revision: Union[str, Sequence[str], None] = "0009_course_facilities_jsonb"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "favorites",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "course_id", name="uq_favorite_user_course"),
    )
    op.create_index("ix_favorites_user_id", "favorites", ["user_id"])
    op.create_index("ix_favorites_course_id", "favorites", ["course_id"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_favorites_course_id", table_name="favorites")
    op.drop_index("ix_favorites_user_id", table_name="favorites")
    op.drop_table("favorites")
