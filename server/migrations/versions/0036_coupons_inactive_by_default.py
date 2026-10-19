"""coupons.is_active 기본값 false + 전부 끄기

쿠폰은 러닝위크 기간에만 지급한다. 운영자가 운영 웹에서 "지급 중"을 켤 때까지 자동 지급이
없도록, 기존 쿠폰을 전부 끄고 기본값도 false로 바꾼다. 이미 발급된 쿠폰은 그대로 쓸 수 있다.

downgrade는 기본값만 되돌린다(끈 값은 되살리지 않는다).

Revision ID: 0036_coupons_inactive_by_default
Revises: 0035_partner_coupon_pin
Create Date: 2026-10-19 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0036_coupons_inactive_by_default"
down_revision: Union[str, Sequence[str], None] = "0035_partner_coupon_pin"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column("coupons", "is_active", server_default=sa.false())
    op.execute("UPDATE coupons SET is_active = false")


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column("coupons", "is_active", server_default=sa.true())
