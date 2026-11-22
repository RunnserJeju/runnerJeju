"""알림: device_tokens, notification_sends, notifications

기기 토큰, 운영자 발송 건, 회원별 알림(발송 명단·알림함·푸시 대기열). 새 테이블뿐이라
기존 데이터·코드에 영향이 없다. 새 테이블이라 RLS도 켠다(0053).

Revision ID: 0054_notifications
Revises: 0053_enable_rls
Create Date: 2026-11-22 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0054_notifications"
down_revision: Union[str, Sequence[str], None] = "0053_enable_rls"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_NOW = sa.text("now()")


def _ts(name: str, *, nullable: bool = True, default: bool = False) -> sa.Column:
    return sa.Column(
        name,
        sa.DateTime(timezone=True),
        server_default=_NOW if default else None,
        nullable=nullable,
    )


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "device_tokens",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.String(length=100), nullable=False),
        sa.Column("token", sa.String(length=500), nullable=False),
        sa.Column("platform", sa.String(length=10), nullable=False),
        sa.Column("permission", sa.String(length=20), nullable=False),
        sa.Column("app_version", sa.String(length=20), nullable=True),
        _ts("authorized_at"),
        _ts("created_at", nullable=False, default=True),
        _ts("updated_at", nullable=False, default=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token"),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])

    op.create_table(
        "notification_sends",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("type", sa.String(length=40), nullable=False),
        sa.Column("title", sa.String(length=100), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("link_url", sa.String(length=500), nullable=True),
        sa.Column("audience", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        _ts("scheduled_at"),
        sa.Column("target_count", sa.Integer(), nullable=False),
        sa.Column("sent_count", sa.Integer(), nullable=False),
        sa.Column("failed_count", sa.Integer(), nullable=False),
        sa.Column("no_device_count", sa.Integer(), nullable=False),
        sa.Column("no_permission_count", sa.Integer(), nullable=False),
        sa.Column("admin_user_id", sa.UUID(), nullable=True),
        sa.Column("admin_username", sa.String(length=100), nullable=True),
        _ts("created_at", nullable=False, default=True),
        _ts("finished_at"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_notification_sends_due",
        "notification_sends",
        ["scheduled_at"],
        postgresql_where=sa.text("status = 'scheduled'"),
    )

    op.create_table(
        "notifications",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("send_id", sa.UUID(), nullable=True),
        sa.Column("user_id", sa.String(length=100), nullable=False),
        sa.Column("type", sa.String(length=40), nullable=False),
        sa.Column("title", sa.String(length=100), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("link_url", sa.String(length=500), nullable=True),
        sa.Column("push_status", sa.String(length=20), server_default="pending", nullable=False),
        sa.Column("push_error", sa.String(length=200), nullable=True),
        sa.Column("attempts", sa.SmallInteger(), server_default="0", nullable=False),
        _ts("next_attempt_at", nullable=False, default=True),
        _ts("claimed_at"),
        _ts("pushed_at"),
        _ts("read_at"),
        _ts("created_at", nullable=False, default=True),
        sa.ForeignKeyConstraint(["send_id"], ["notification_sends.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_notifications_send_id", "notifications", ["send_id"])
    op.create_index("ix_notifications_user_created", "notifications", ["user_id", "created_at"])
    op.create_index("ix_notifications_type_created", "notifications", ["type", "created_at"])
    op.create_index(
        "ix_notifications_pending",
        "notifications",
        ["next_attempt_at"],
        postgresql_where=sa.text("push_status = 'pending'"),
    )
    op.create_index(
        "ix_notifications_sending",
        "notifications",
        ["claimed_at"],
        postgresql_where=sa.text("push_status = 'sending'"),
    )
    op.create_index(
        "ix_notifications_unread",
        "notifications",
        ["user_id"],
        postgresql_where=sa.text("read_at IS NULL"),
    )
    for table in ("device_tokens", "notification_sends", "notifications"):
        op.execute(f"ALTER TABLE public.{table} ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("notifications")
    op.drop_table("notification_sends")
    op.drop_table("device_tokens")
