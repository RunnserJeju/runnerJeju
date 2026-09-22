"""courses.distance_km 정수 → 소수 첫째 자리(Numeric(5,1))

운영진이 8.3km처럼 소수점 거리를 입력하려는 요구. 기존 정수 값은 그대로 8.0이 된다.

Revision ID: 0025_course_distance_decimal
Revises: 0024_user_log
Create Date: 2026-09-20 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0025_course_distance_decimal"
down_revision: Union[str, Sequence[str], None] = "0024_user_log"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column(
        "courses",
        "distance_km",
        existing_type=sa.Integer(),
        type_=sa.Numeric(5, 1),
        existing_nullable=False,
        postgresql_using="distance_km::numeric(5,1)",
    )


def downgrade() -> None:
    """Downgrade schema. 소수는 반올림해 정수로 되돌린다."""
    op.alter_column(
        "courses",
        "distance_km",
        existing_type=sa.Numeric(5, 1),
        type_=sa.Integer(),
        existing_nullable=False,
        postgresql_using="round(distance_km)::integer",
    )
