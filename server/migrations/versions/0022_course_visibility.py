"""courses.visibility 추가 (운영자 전용 테스트 코스)

'public'이면 모두에게, 'admin'이면 role='admin'인 앱 사용자에게만 내려간다.
기본값을 두지 않아 등록할 때 반드시 정하게 한다. NULL은 공개가 아니므로
일반 사용자에게는 보이지 않는다. 이미 올라가 있던 코스는 서비스 중이라
'public'으로 채운다.

Revision ID: 0022_course_visibility
Revises: 0021_coupons
Create Date: 2026-09-07 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0022_course_visibility"
down_revision: Union[str, Sequence[str], None] = "0021_coupons"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("courses", sa.Column("visibility", sa.String(20), nullable=True))
    op.execute("UPDATE courses SET visibility = 'public' WHERE visibility IS NULL")


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("courses", "visibility")
