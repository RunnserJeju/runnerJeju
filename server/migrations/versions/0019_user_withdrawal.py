"""users에 last_login_at / deleted_at 추가 (회원 탈퇴 + 활성 통계)

회원 탈퇴는 hard delete가 아니라 soft delete + 익명화다 — 탈퇴 시 users 행은
남기되 PII(email·닉네임·프로필·provider id)를 스크럽하고 deleted_at을 찍는다.
활동(완주·찜)은 익명 상태로 남겨 코스 통계의 역사적 누적을 유지한다.

last_login_at은 로그인/토큰 리프레시 때 갱신하며, 활성 이용자 통계·휴면 판정에
쓴다. 둘 다 nullable이라 기존 행 백필은 필요 없다.

Revision ID: 0019_user_withdrawal
Revises: 0018_users_created_index
Create Date: 2026-09-06 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0019_user_withdrawal"
down_revision: Union[str, Sequence[str], None] = "0018_users_created_index"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "users",
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("users", "deleted_at")
    op.drop_column("users", "last_login_at")
