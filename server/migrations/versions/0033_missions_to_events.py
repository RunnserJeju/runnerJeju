"""missions → events (#70)

이벤트 미션(missions)은 운영 API만 있고 앱·운영 웹 어디서도 쓰지 않았다(개발 DB 0건).
커뮤니티 이벤트(그림 + 게시글)로 고쳐 쓴다.

- 테이블 이름 missions → events.
- 자유 텍스트 달성 조건·리워드(condition, reward)는 지운다.
- 이미지(image_url)를 추가한다.

missions에 행이 있으면 condition·reward가 사라지므로 멈춘다 — 값을 옮길 곳을 정한 뒤
다시 돌린다.

downgrade는 테이블 이름과 컬럼만 되살린다(condition·reward는 빈 문자열).

Revision ID: 0033_missions_to_events
Revises: 0032_coupon_rules
Create Date: 2026-10-18 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0033_missions_to_events"
down_revision: Union[str, Sequence[str], None] = "0032_coupon_rules"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    count = op.get_bind().execute(sa.text("SELECT count(*) FROM missions")).scalar()
    if count:
        raise RuntimeError(
            f"missions에 행이 {count}개 있어요. condition·reward를 지우기 전에 옮길 곳을 정해 주세요."
        )

    op.rename_table("missions", "events")
    op.execute("ALTER TABLE events RENAME CONSTRAINT missions_pkey TO events_pkey")
    op.drop_column("events", "condition")
    op.drop_column("events", "reward")
    op.add_column("events", sa.Column("image_url", sa.String(500), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("events", "image_url")
    op.add_column(
        "events",
        sa.Column("reward", sa.String(500), nullable=False, server_default=""),
    )
    op.add_column(
        "events",
        sa.Column("condition", sa.String(500), nullable=False, server_default=""),
    )
    op.execute("ALTER TABLE events RENAME CONSTRAINT events_pkey TO missions_pkey")
    op.rename_table("events", "missions")
