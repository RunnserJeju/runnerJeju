"""admin_users / admin_sessions 테이블 생성

운영 웹의 세션 로그인. 공유 API 키(ADMIN_API_KEY 헤더) 방식을 대체한다 —
운영자별 아이디/비밀번호로 로그인하고, 서버가 발급한 세션 쿠키로 /admin/*에
접근한다. 앱 사용자(users)와 완전히 별개다(앱은 소셜 로그인 전용, 비번 없음).

admin_users: 운영자 계정(bcrypt 비번 해시). 가입 API 없이 tools/create_admin.py로 시드.
admin_sessions: 로그인 세션. 쿠키엔 불투명 토큰, 여기엔 그 sha256 해시만 저장.

Revision ID: 0015_admin_auth
Revises: 0014_missions
Create Date: 2026-09-03 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0015_admin_auth"
down_revision: Union[str, Sequence[str], None] = "0014_missions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "admin_users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("username", sa.String(50), nullable=False),
        sa.Column("password_hash", sa.String(100), nullable=False),
        sa.Column("display_name", sa.String(100), nullable=True),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        op.f("ix_admin_users_username"),
        "admin_users",
        ["username"],
        unique=True,
    )

    op.create_table(
        "admin_sessions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("admin_user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["admin_user_id"], ["admin_users.id"]),
    )
    op.create_index(
        op.f("ix_admin_sessions_admin_user_id"),
        "admin_sessions",
        ["admin_user_id"],
    )
    op.create_index(
        op.f("ix_admin_sessions_token_hash"),
        "admin_sessions",
        ["token_hash"],
        unique=True,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f("ix_admin_sessions_token_hash"), table_name="admin_sessions")
    op.drop_index(
        op.f("ix_admin_sessions_admin_user_id"), table_name="admin_sessions"
    )
    op.drop_table("admin_sessions")
    op.drop_index(op.f("ix_admin_users_username"), table_name="admin_users")
    op.drop_table("admin_users")
