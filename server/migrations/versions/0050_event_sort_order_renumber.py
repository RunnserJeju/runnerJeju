"""이벤트 순서를 0부터 다시 매긴다(운영툴 ↑↓ 순서 조정으로 바꾸면서)

예전에는 운영자가 이벤트마다 정렬 숫자를 직접 넣었다(같은 숫자도 가능, 같으면 최신순).
이제 운영툴은 목록 순서를 통째로 저장한다(PUT /admin/events/order). 지금 앱에 보이는
순서(sort_order, 같으면 최신순) 그대로 0부터 번호를 매겨, 배포해도 순서가 바뀌지 않게 한다.
컬럼은 그대로다.

Revision ID: 0050_event_sort_order_renumber
Revises: 0049_notice_sort_order
Create Date: 2026-11-08 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0050_event_sort_order_renumber"
down_revision: Union[str, Sequence[str], None] = "0049_notice_sort_order"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute(
        """
        UPDATE events
        SET sort_order = ranked.position
        FROM (
            SELECT id,
                   ROW_NUMBER() OVER (ORDER BY sort_order, created_at DESC) - 1 AS position
            FROM events
        ) AS ranked
        WHERE events.id = ranked.id
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    # 옛 번호는 남기지 않았다. 다시 매긴 번호도 같은 순서를 뜻하므로 되돌릴 것이 없다.
