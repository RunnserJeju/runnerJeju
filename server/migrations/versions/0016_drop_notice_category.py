"""notices.category 제거

공지 카테고리(0013에서 추가)는 쓰지 않기로 해서 컬럼을 뗀다. 노출 기간
(starts_at/ends_at)은 그대로 둔다.

downgrade는 NOT NULL 복원을 위해 기존 행을 'etc'로 채운 뒤 기본값을 뗀다(0013과 같은 방식).

Revision ID: 0016_drop_notice_category
Revises: 0015_admin_auth
Create Date: 2026-09-05 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0016_drop_notice_category"
down_revision: Union[str, Sequence[str], None] = "0015_admin_auth"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.drop_column("notices", "category")


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column(
        "notices",
        sa.Column("category", sa.String(20), nullable=False, server_default="etc"),
    )
    op.alter_column("notices", "category", server_default=None)
