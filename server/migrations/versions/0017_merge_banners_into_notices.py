"""배너를 공지에 합침 — notices.image_url 추가, banners 테이블 제거

홈 상단 배너가 곧 공지 내용이라 별도 리소스로 둘 이유가 없었다. 공지에 이미지
컬럼을 붙이고, 이미지가 있는 공지를 앱이 배너로 그린다.

기존 배너 행은 버리지 않고 공지로 옮긴다(이미지 URL 그대로 — Storage 파일은
손대지 않는다). 배너엔 제목·본문이 없어서 자리표시 문구를 넣으니 운영자가
공지 수정으로 채우면 된다. 비활성(is_active=false) 배너는 ends_at을 과거로 둬서
옮긴 뒤에도 앱에 안 보이게 한다.

Revision ID: 0017_merge_banners_into_notices
Revises: 0016_drop_notice_category
Create Date: 2026-09-05 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0017_merge_banners_into_notices"
down_revision: Union[str, Sequence[str], None] = "0016_drop_notice_category"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PLACEHOLDER_TITLE = "(배너) 제목을 입력해 주세요"
PLACEHOLDER_BODY = "옛 배너에서 옮겨진 공지예요. 제목과 내용을 채워 주세요."


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "notices", sa.Column("image_url", sa.String(500), nullable=True)
    )

    # 배너 → 공지 이관. created_at을 유지해 목록 순서(최신순)가 흔들리지 않게 한다.
    op.execute(
        f"""
        INSERT INTO notices (id, title, body, image_url, starts_at, ends_at, created_at)
        SELECT id,
               '{PLACEHOLDER_TITLE}',
               '{PLACEHOLDER_BODY}',
               image_url,
               NULL,
               CASE WHEN is_active THEN NULL ELSE created_at END,
               created_at
        FROM banners
        """
    )

    op.drop_table("banners")


def downgrade() -> None:
    """Downgrade schema."""
    op.create_table(
        "banners",
        sa.Column("id", sa.UUID(as_uuid=True), primary_key=True),
        sa.Column("image_url", sa.String(500), nullable=False),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("created_by", sa.String(100), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    # 이미지 있는 공지를 배너로 되돌린다. 제목·본문은 배너에 자리가 없어 버려진다.
    op.execute(
        """
        INSERT INTO banners (id, image_url, sort_order, is_active, created_by, created_at)
        SELECT id, image_url, 0, TRUE, 'migration', created_at
        FROM notices
        WHERE image_url IS NOT NULL
        """
    )
    op.drop_column("notices", "image_url")
