"""쿠폰 추첨 지급 — 확률(win_rate_percent)·재고(stock)·사용 방식(redeem_type)·쿠폰 코드·추첨 기록

- coupons.win_rate_percent: 조건을 채웠을 때 지급될 확률(%). 100이면 확정 지급. 코스 완주 쿠폰은
  33으로 바꾼다(사양 변경).
- coupons.stock: 총 발급 수량. null이면 무제한. 발급 수가 원본이고 이 값은 상한이다. 스페셜 쿠폰은
  선착순 3장.
- coupons.redeem_type: 'partner_pin'(업체 번호 입력) | 'kakao_channel'(카카오톡 채널 문의 후 운영자가
  지급완료 처리). 기존 행은 partner_pin.
- coupons.trigger_params: bingo_lines 조건의 {lines}.
- user_coupons.code: 운영자가 캡처에서 사용자를 찾는 식별 코드. 기존 행도 채운다.
- coupon_draws: (쿠폰, 사용자, grant_key)당 한 번의 추첨 결과(won|lost|sold_out). 낙첨도 남겨
  다시 뽑지 않는다.
- bingo_lines 템플릿 3개(1·3·5줄)를 꺼진 채로 심는다. 수령 기한은 진행 중인 회차 종료 + 30일.

Revision ID: 0043_coupon_draws
Revises: 0042_rw_event_visibility
Create Date: 2026-10-31 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0043_coupon_draws"
down_revision: Union[str, Sequence[str], None] = "0042_rw_event_visibility"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# 헷갈리는 글자(0 O 1 I)를 뺀 32자. app/coupon_rules.new_code와 같다.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

_REWARDS = (
    (1, 33, 90, "탐나는전"),
    (3, 33, 30, "핫스프링 앤 스파 종합권"),
    (5, 50, 4, "삼다정 뷔페 이용권 1인 2매"),
)


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "coupons",
        sa.Column("win_rate_percent", sa.Integer, nullable=False, server_default="100"),
    )
    op.add_column("coupons", sa.Column("stock", sa.Integer, nullable=True))
    op.add_column(
        "coupons",
        sa.Column("redeem_type", sa.String(20), nullable=False, server_default="partner_pin"),
    )
    op.add_column("coupons", sa.Column("trigger_params", JSONB, nullable=True))
    op.execute("UPDATE coupons SET win_rate_percent = 33 WHERE trigger_type = 'course_complete'")
    op.execute("UPDATE coupons SET stock = 3 WHERE trigger_type = 'bingo_complete'")

    op.add_column("user_coupons", sa.Column("code", sa.String(12), nullable=True))
    # 서브쿼리로 만들면 행마다 재평가되지 않아(InitPlan) 같은 코드가 들어간다. 식으로 펼친다.
    char = f"substr('{_CODE_ALPHABET}', 1 + floor(random() * 32)::int, 1)"
    group = " || ".join([char] * 4)
    op.execute(f"UPDATE user_coupons SET code = {group} || '-' || {group}")
    op.alter_column("user_coupons", "code", nullable=False)
    op.create_index("ux_user_coupons_code", "user_coupons", ["code"], unique=True)

    op.create_table(
        "coupon_draws",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "coupon_id",
            UUID(as_uuid=True),
            sa.ForeignKey("coupons.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column("grant_key", sa.String(100), nullable=False),
        sa.Column("result", sa.String(10), nullable=False),
        sa.Column(
            "user_coupon_id",
            UUID(as_uuid=True),
            sa.ForeignKey("user_coupons.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "run_id", UUID(as_uuid=True), sa.ForeignKey("runs.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column(
            "drawn_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("coupon_id", "user_id", "grant_key", name="uq_coupon_draw"),
    )
    op.create_index("ix_coupon_draws_user_id", "coupon_draws", ["user_id"])
    op.create_index("ix_coupon_draws_coupon_id", "coupon_draws", ["coupon_id"])

    for lines, percent, stock, benefit in _REWARDS:
        op.execute(
            f"""
            INSERT INTO coupons
              (id, name, benefit, description, trigger_type, trigger_params, redeem_type,
               win_rate_percent, stock, is_active, valid_until)
            VALUES (
              gen_random_uuid(), '{lines}줄 리워드', '{benefit}',
              '러닝위크 빙고 {lines}줄을 완성하면 추첨으로 드리는 경품이에요.',
              'bingo_lines', '{{"lines": {lines}}}'::jsonb, 'kakao_channel',
              {percent}, {stock}, false,
              (SELECT max(ends_at) + interval '30 days' FROM running_weeks WHERE is_active)
            )
            """
        )


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DELETE FROM coupons WHERE trigger_type = 'bingo_lines'")
    op.drop_index("ix_coupon_draws_coupon_id", table_name="coupon_draws")
    op.drop_index("ix_coupon_draws_user_id", table_name="coupon_draws")
    op.drop_table("coupon_draws")
    op.drop_index("ux_user_coupons_code", table_name="user_coupons")
    op.drop_column("user_coupons", "code")
    for column in ("trigger_params", "redeem_type", "stock", "win_rate_percent"):
        op.drop_column("coupons", column)
