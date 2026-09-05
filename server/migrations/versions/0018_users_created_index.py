"""users(created_at, id) 회원 목록 정렬용 복합 인덱스

운영 웹 회원 목록(GET /admin/users)이 가입일 최신순 + id 2차키로 페이지네이션한다.
복합 인덱스로 정렬을 인덱스 순서대로 읽어 전체 정렬을 피한다. PostgreSQL은 이
오름차순 인덱스를 역방향으로 읽어 ORDER BY created_at DESC, id DESC도 처리하므로
인덱스 자체는 오름차순으로 둔다. 나중에 keyset 페이지네이션으로 바꿔도 같은 인덱스를
그대로 쓴다.

Revision ID: 0018_users_created_index
Revises: 0017_merge_banners_into_notices
Create Date: 2026-09-05 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0018_users_created_index"
down_revision: Union[str, Sequence[str], None] = "0017_merge_banners_into_notices"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_index("ix_users_created_at_id", "users", ["created_at", "id"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_users_created_at_id", table_name="users")
