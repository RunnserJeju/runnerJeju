"""user_log.user_time — 앱에서 로그가 발생한 시각(기기 시계)

created_at은 서버 수신 시각이라 한 묶음이 같은 값을 갖는다. 옛 앱 버전과 서버가 직접
쓰는 로그는 null로 남는다.

Revision ID: 0055_user_log_user_time
Revises: 0054_notifications
Create Date: 2026-11-28 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0055_user_log_user_time"
down_revision: Union[str, Sequence[str], None] = "0054_notifications"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("user_log", sa.Column("user_time", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("user_log", "user_time")
