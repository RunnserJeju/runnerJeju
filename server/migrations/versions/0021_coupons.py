"""coupons / user_coupons 테이블 생성 (쿠폰 관리)

쿠폰 템플릿(coupons)을 운영자가 제작하고, 유저에게 발급(user_coupons)한다. 발급분은
템플릿을 라이브 참조하므로 혜택/이름을 복사하지 않는다. 상태는 user_coupons.used_at
하나로(null=미사용, 값=사용완료), '만료'는 coupons.valid_until로 계산한다.

템플릿 삭제 시 발급분·사용기록이 함께 사라지도록 FK를 ON DELETE CASCADE로 건다
(운영 웹이 "진짜 삭제?"를 확인한 뒤 삭제).

Revision ID: 0021_coupons
Revises: 0020_course_views
Create Date: 2026-09-06 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0021_coupons"
down_revision: Union[str, Sequence[str], None] = "0020_course_views"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "coupons",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.String(2000), nullable=True),
        sa.Column("benefit", sa.String(500), nullable=False),
        sa.Column("valid_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_table(
        "user_coupons",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("coupon_id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column(
            "issued_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["coupon_id"], ["coupons.id"], ondelete="CASCADE"
        ),
    )
    op.create_index(
        op.f("ix_user_coupons_coupon_id"), "user_coupons", ["coupon_id"]
    )
    op.create_index(
        op.f("ix_user_coupons_user_id"), "user_coupons", ["user_id"]
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f("ix_user_coupons_user_id"), table_name="user_coupons")
    op.drop_index(op.f("ix_user_coupons_coupon_id"), table_name="user_coupons")
    op.drop_table("user_coupons")
    op.drop_table("coupons")
