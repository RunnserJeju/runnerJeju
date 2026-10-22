"""빙고 보상 — 스페셜 쿠폰(bingo_complete) 행 + user_coupons.run_id

- 러닝위크 빙고판 25칸을 다 채우면(=25개 코스 완주) 주는 '스페셜 쿠폰'을 심는다.
  혜택은 코스 완주 쿠폰과 같게 복사하고, 다른 쿠폰처럼 꺼진 채로 시작한다.
- user_coupons.run_id: 달려서 받은 쿠폰의 러닝. 완주 결과 화면이 이번에 받은 쿠폰을 찾는다.

빙고 N줄 스탬프는 스탬프 조건(bingo_lines)이라 운영툴에서 행을 만든다.

Revision ID: 0037_bingo_rewards
Revises: 0036_coupons_inactive_by_default
Create Date: 2026-10-21 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0037_bingo_rewards"
down_revision: Union[str, Sequence[str], None] = "0036_coupons_inactive_by_default"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "user_coupons",
        sa.Column(
            "run_id",
            UUID(as_uuid=True),
            sa.ForeignKey("runs.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.execute(
        """
        INSERT INTO coupons (id, name, benefit, description, trigger_type, is_active)
        VALUES (
          gen_random_uuid(),
          '스페셜 쿠폰',
          COALESCE(
            (SELECT benefit FROM coupons WHERE trigger_type = 'course_complete'
             ORDER BY created_at LIMIT 1),
            '협력 업체에서 혜택을 확인해주세요'
          ),
          '러닝위크 25개 코스를 모두 완주하면 받는 쿠폰이에요.',
          'bingo_complete',
          false
        )
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DELETE FROM coupons WHERE trigger_type = 'bingo_complete'")
    op.drop_column("user_coupons", "run_id")
