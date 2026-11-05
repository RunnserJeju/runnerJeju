"""공지 앱 실행 시 노출 — notices.show_on_launch

켜진 공지는 앱을 켜자마자 팝업으로 뜬다(앱은 실행당 한 번, 켜진 공지 중 가장 최근 것 하나).

Revision ID: 0046_notice_show_on_launch
Revises: 0045_partner_visibility
Create Date: 2026-11-06 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0046_notice_show_on_launch"
down_revision: Union[str, Sequence[str], None] = "0045_partner_visibility"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "notices",
        sa.Column("show_on_launch", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("notices", "show_on_launch")
