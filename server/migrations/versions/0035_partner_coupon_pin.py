"""partners.coupon_pin — 업체별 쿠폰 사용 번호

쿠폰 사용을 "업체 이름 골라 사용하기"에서 "업체 고유 4자리 번호 입력"으로 바꾼다.
업체마다 번호가 달라야 어느 업체에서 썼는지 가려지므로 unique다. 값은 운영 웹에서 넣는다.

Revision ID: 0035_partner_coupon_pin
Revises: 0034_user_coupon_expired_at
Create Date: 2026-10-19 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0035_partner_coupon_pin"
down_revision: Union[str, Sequence[str], None] = "0034_user_coupon_expired_at"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("partners", sa.Column("coupon_pin", sa.String(4), nullable=True))
    op.create_unique_constraint("uq_partners_coupon_pin", "partners", ["coupon_pin"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint("uq_partners_coupon_pin", "partners", type_="unique")
    op.drop_column("partners", "coupon_pin")
