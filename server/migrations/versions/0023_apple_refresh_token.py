"""users.apple_refresh_token 추가 (탈퇴 시 Apple 연결 해제용)

앱스토어 계정 삭제 요건으로 탈퇴 시 Apple 토큰을 revoke해야 한다. 그 호출에
필요한 refresh 토큰을 로그인 때 받아 여기 보관한다.

Revision ID: 0023_apple_refresh_token
Revises: 0022_course_visibility
Create Date: 2026-09-12 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0023_apple_refresh_token"
down_revision: Union[str, Sequence[str], None] = "0022_course_visibility"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("users", sa.Column("apple_refresh_token", sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("users", "apple_refresh_token")
