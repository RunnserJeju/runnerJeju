"""협력업체 썸네일·추가 이미지 — partners.thumbnail_url, partners.image_urls

코스(0039)와 같은 구조. 썸네일은 목록 카드에, 추가 이미지는 상세 시트 맨 위 갤러리에
나온다. 파일은 Storage `partner-images` 버킷(storage.SUPABASE_PARTNER_BUCKET).

Revision ID: 0041_partner_images
Revises: 0040_stamp_category_images
Create Date: 2026-10-24 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0041_partner_images"
down_revision: Union[str, Sequence[str], None] = "0040_stamp_category_images"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("partners", sa.Column("thumbnail_url", sa.String(500), nullable=True))
    op.add_column(
        "partners",
        sa.Column("image_urls", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("partners", "image_urls")
    op.drop_column("partners", "thumbnail_url")
