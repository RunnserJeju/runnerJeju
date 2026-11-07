"""쿠폰 회수(user_coupons.revoked_at/revoked_reason) + 운영자 행위 로그(admin_actions)

회수는 지우지 않고 시각·사유를 남긴다. 앱은 회수된 쿠폰을 내려주지 않고, 사용 시도는 410.
운영툴에서 한 지급·회수·완주 인정은 admin_actions에 누가 언제 무엇을 했는지 남는다.

Revision ID: 0047_coupon_revoke_admin_actions
Revises: 0046_notice_show_on_launch
Create Date: 2026-11-08 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0047_coupon_revoke_admin_actions"
down_revision: Union[str, Sequence[str], None] = "0046_notice_show_on_launch"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "user_coupons", sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "user_coupons", sa.Column("revoked_reason", sa.String(length=200), nullable=True)
    )
    op.create_table(
        "admin_actions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "admin_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("admin_users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("admin_username", sa.String(length=50), nullable=False),
        sa.Column("action", sa.String(length=50), nullable=False),
        sa.Column("target_type", sa.String(length=30), nullable=False),
        sa.Column("target_id", sa.String(length=100), nullable=True),
        sa.Column("user_id", sa.String(length=100), nullable=True),
        sa.Column(
            "detail", postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_admin_actions_user_id", "admin_actions", ["user_id"])
    op.create_index("ix_admin_actions_created_at", "admin_actions", ["created_at"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_admin_actions_created_at", table_name="admin_actions")
    op.drop_index("ix_admin_actions_user_id", table_name="admin_actions")
    op.drop_table("admin_actions")
    op.drop_column("user_coupons", "revoked_reason")
    op.drop_column("user_coupons", "revoked_at")
