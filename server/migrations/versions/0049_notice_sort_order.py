"""공지 노출 순서(notices.sort_order)

운영툴에서 공지 순서를 정한다. 홈 배너·공지 목록·실행 시 팝업이 이 순서를 따른다.
기존 공지는 지금 앱에 보이는 순서(최신순) 그대로 0부터 번호를 매겨, 배포해도 순서가
바뀌지 않게 한다.

Revision ID: 0049_notice_sort_order
Revises: 0048_run_continuations
Create Date: 2026-11-08 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0049_notice_sort_order"
down_revision: Union[str, Sequence[str], None] = "0048_run_continuations"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "notices",
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    op.execute(
        """
        UPDATE notices
        SET sort_order = ranked.position
        FROM (
            SELECT id, ROW_NUMBER() OVER (ORDER BY created_at DESC) - 1 AS position
            FROM notices
        ) AS ranked
        WHERE notices.id = ranked.id
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("notices", "sort_order")
