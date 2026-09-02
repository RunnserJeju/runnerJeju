"""missions 테이블 생성

이벤트 미션. 운영자가 참여 기간·달성 조건·리워드·내용을 설정한다. 달성 조건과
리워드는 자유 텍스트다 — 자동 판정(런타임)은 아직 만들지 않으므로, 운영자가
서술하면 앱이 그대로 보여주는 단계다. 나중에 자동 판정이 필요해지면 그때
condition을 타입+목표값으로 구조화한다.

참여 기간(starts_at/ends_at)은 둘 다 nullable이고 null은 "제한 없음"이다(공지와
같은 규칙). is_active/sort_order는 노출 제어·정렬용으로 배너와 같다.

Revision ID: 0014_missions
Revises: 0013_notice_category_period
Create Date: 2026-09-02 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0014_missions"
down_revision: Union[str, Sequence[str], None] = "0013_notice_category_period"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "missions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("condition", sa.String(500), nullable=False),
        sa.Column("reward", sa.String(500), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "is_active", sa.Boolean(), nullable=False, server_default=sa.true()
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
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


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("missions")
