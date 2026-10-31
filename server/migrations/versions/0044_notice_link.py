"""공지 연결 버튼 — notices.link_url, notices.link_label

공지 상세 아래 버튼 하나. link_url은 외부 주소(http/https, 운영툴에서 입력)거나 앱 화면
(`app:running-week` 등, 개발자가 DB에 직접 넣음 — 운영툴은 이 값을 만들거나 바꾸지 못한다).
link_label은 버튼 문구, null이면 앱 기본 문구.

Revision ID: 0044_notice_link
Revises: 0043_coupon_draws
Create Date: 2026-10-31 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0044_notice_link"
down_revision: Union[str, Sequence[str], None] = "0043_coupon_draws"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("notices", sa.Column("link_url", sa.String(500), nullable=True))
    op.add_column("notices", sa.Column("link_label", sa.String(40), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("notices", "link_label")
    op.drop_column("notices", "link_url")
