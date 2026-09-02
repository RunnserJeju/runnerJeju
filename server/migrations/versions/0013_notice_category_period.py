"""notices에 category / starts_at / ends_at 추가

공지사항에 카테고리와 노출 기간을 붙인다.

category는 고정 5종(app_guide/new_course/event/maintenance/etc) 중 하나로, 앱이
라벨·칩 색을 매핑한다. 운영자가 카테고리를 직접 추가하지는 않는다 — "기타(etc)"가
그 외 케이스를 흡수하므로 별도 카테고리 관리가 필요 없다.

기존 공지 행이 있으므로 NOT NULL인 category엔 server_default('etc')를 붙여 채운
뒤 기본값을 뗀다(0009가 JSONB에 쓴 방식과 같다 — 이후 삽입은 앱이 값을 준다).

노출 기간(starts_at/ends_at)은 둘 다 nullable이다 — null은 "제한 없음"이라
starts_at=null은 즉시부터, ends_at=null은 무기한 노출을 뜻한다.

Revision ID: 0013_notice_category_period
Revises: 0012_course_stamp_image
Create Date: 2026-09-02 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0013_notice_category_period"
down_revision: Union[str, Sequence[str], None] = "0012_course_stamp_image"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "notices",
        sa.Column("category", sa.String(20), nullable=False, server_default="etc"),
    )
    # 기본값은 기존 행을 채우기 위한 것일 뿐 — 모델(값 필수)과 겹치지 않게 떼어 둔다.
    op.alter_column("notices", "category", server_default=None)

    op.add_column(
        "notices", sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "notices", sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("notices", "ends_at")
    op.drop_column("notices", "starts_at")
    op.drop_column("notices", "category")
