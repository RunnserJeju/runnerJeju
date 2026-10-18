"""user_coupons.expired_at — 만료를 저장한다

만료는 coupons.valid_until로 계산만 하던 것을, 서버가 알아챈 시점(내 쿠폰 조회·사용 시도)에
user_coupons.expired_at에 남긴다. 앱 목록에서는 빠지고 운영툴 발급 현황에는 '만료'로 보인다.

Revision ID: 0034_user_coupon_expired_at
Revises: 0033_missions_to_events
Create Date: 2026-10-18 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0034_user_coupon_expired_at"
down_revision: Union[str, Sequence[str], None] = "0033_missions_to_events"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "user_coupons", sa.Column("expired_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("user_coupons", "expired_at")
