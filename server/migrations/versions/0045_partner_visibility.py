"""partners.visibility 추가 (앱에 숨길 협력업체)

코스(0022)와 같은 규칙으로 'public' | 'admin'. admin이면 role='admin'인 앱 사용자에게만
내려간다. 기본은 'public'이되, 쿠폰 번호(coupon_pin)가 없는 업체는 아직 계약이 안 끝난
곳이라 'admin'으로 숨긴다(운영자 결정, 2026-11-03).

Revision ID: 0045_partner_visibility
Revises: 0044_notice_link
Create Date: 2026-11-03 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0045_partner_visibility"
down_revision: Union[str, Sequence[str], None] = "0044_notice_link"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "partners",
        sa.Column("visibility", sa.String(20), nullable=False, server_default="public"),
    )
    op.execute("UPDATE partners SET visibility = 'admin' WHERE coupon_pin IS NULL")


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("partners", "visibility")
