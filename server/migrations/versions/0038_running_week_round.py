"""러닝위크 회차 번호 — running_weeks.round

러닝위크 전용 스탬프(running_week_course)가 몇 회차 것인지 데이터로 구분한다. 앱에 내리는
이름에는 회차를 넣지 않는다. 기존 행은 등록순으로 1부터 매긴다.

Revision ID: 0038_running_week_round
Revises: 0037_bingo_rewards
Create Date: 2026-10-22 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0038_running_week_round"
down_revision: Union[str, Sequence[str], None] = "0037_bingo_rewards"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("running_weeks", sa.Column("round", sa.Integer(), nullable=True))
    op.execute(
        """
        UPDATE running_weeks w SET round = n.rn
        FROM (SELECT id, row_number() OVER (ORDER BY created_at) AS rn FROM running_weeks) n
        WHERE w.id = n.id
        """
    )
    op.alter_column("running_weeks", "round", nullable=False)
    op.create_unique_constraint("uq_running_weeks_round", "running_weeks", ["round"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint("uq_running_weeks_round", "running_weeks", type_="unique")
    op.drop_column("running_weeks", "round")
