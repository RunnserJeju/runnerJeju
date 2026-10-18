"""쿠폰 지급 규칙·사용 업체 — coupons.trigger_type, coupon_partners, user_coupons.grant_key

쿠폰 템플릿은 코드가 심고(운영툴은 수정만), 지급 조건은 스탬프처럼 trigger_type으로
가른다. 지금은 manual(운영자 지급)과 course_complete(아무 코스나 완주하면 한 장)뿐이고
조건이 늘면 규칙 코드 + 행 하나를 같이 더한다(app/coupon_rules.py).

- coupons.trigger_type / is_active 추가. 기존 행은 전부 manual.
- coupon_partners: 쿠폰을 쓸 수 있는 업체. 행이 없으면 모든 업체 허용.
- user_coupons.grant_key: 자동 발급의 중복 방지 키(코스완료는 "course:{id}"). 운영자
  수동 지급은 null이라 같은 사람에게 여러 장 가능.
- user_coupons.used_partner_id: 어느 업체에서 썼는지(업체 이용률).
- manual 한 장, course_complete 한 장을 심는다.

Revision ID: 0032_coupon_rules
Revises: 0031_running_weeks
Create Date: 2026-10-18 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0032_coupon_rules"
down_revision: Union[str, Sequence[str], None] = "0031_running_weeks"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "coupons",
        sa.Column("trigger_type", sa.String(30), nullable=False, server_default="manual"),
    )
    op.add_column(
        "coupons",
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )

    op.create_table(
        "coupon_partners",
        sa.Column(
            "coupon_id",
            UUID(as_uuid=True),
            sa.ForeignKey("coupons.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "partner_id",
            UUID(as_uuid=True),
            sa.ForeignKey("partners.id", ondelete="CASCADE"),
            primary_key=True,
        ),
    )
    op.create_index("ix_coupon_partners_partner_id", "coupon_partners", ["partner_id"])

    op.add_column("user_coupons", sa.Column("grant_key", sa.String(100), nullable=True))
    op.create_unique_constraint(
        "uq_user_coupon_grant", "user_coupons", ["coupon_id", "user_id", "grant_key"]
    )
    op.add_column(
        "user_coupons",
        sa.Column(
            "used_partner_id",
            UUID(as_uuid=True),
            sa.ForeignKey("partners.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("ix_user_coupons_used_partner_id", "user_coupons", ["used_partner_id"])

    op.execute(
        """
        INSERT INTO coupons (id, name, benefit, description, trigger_type)
        VALUES
          (gen_random_uuid(), '운영자 지급 쿠폰', '협력 업체에서 혜택을 확인해주세요', NULL, 'manual'),
          (gen_random_uuid(), '코스 완주 쿠폰', '협력 업체에서 혜택을 확인해주세요',
           '코스를 완주하면 받는 쿠폰이에요.', 'course_complete')
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    # 자동 지급 쿠폰은 돌아갈 자리가 없어 발급분과 함께 지운다(cascade).
    op.execute("DELETE FROM coupons WHERE trigger_type <> 'manual'")

    op.drop_index("ix_user_coupons_used_partner_id", table_name="user_coupons")
    op.drop_column("user_coupons", "used_partner_id")
    op.drop_constraint("uq_user_coupon_grant", "user_coupons", type_="unique")
    op.drop_column("user_coupons", "grant_key")

    op.drop_index("ix_coupon_partners_partner_id", table_name="coupon_partners")
    op.drop_table("coupon_partners")

    op.drop_column("coupons", "is_active")
    op.drop_column("coupons", "trigger_type")
