"""courses에 stamp_image_url 추가, stamps.image_url 제거

코스 완주 시 주는 스탬프 도안을 코스에 붙인다. 스탬프는 코스에 1:1 종속이라
도안도 코스가 갖고, 발급된 스탬프(stamps)는 조회 시 이 값을 라이브로 참조한다.

**stamps.image_url을 지운다.** 원래 스탬프 도안을 담으려던 컬럼인데 발급 로직이
한 번도 채운 적이 없어 항상 NULL이었다(죽은 컬럼). 도안 출처를 코스로 옮기면
역할이 겹치므로 없앤다. 항상 NULL이라 옮길 데이터도 없어 그냥 drop한다.

두 courses 컬럼은 nullable이라 server_default가 필요 없다(0011이 thumbnail_url을
붙인 방식과 같다). 기존 코스는 도안이 없어도 되는 항목이라 NULL로 둔다.

Revision ID: 0012_course_stamp_image
Revises: 0011_course_thumb_eta
Create Date: 2026-09-02 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0012_course_stamp_image"
down_revision: Union[str, Sequence[str], None] = "0011_course_thumb_eta"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "courses", sa.Column("stamp_image_url", sa.String(500), nullable=True)
    )
    # 항상 NULL이던 죽은 컬럼 — 도안 출처가 courses로 옮겨가 역할이 겹쳐 제거한다.
    op.drop_column("stamps", "image_url")


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column(
        "stamps", sa.Column("image_url", sa.String(500), nullable=True)
    )
    op.drop_column("courses", "stamp_image_url")
