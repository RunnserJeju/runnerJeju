"""러닝위크·참가 신청 테이블 추가 (#70)

- running_weeks: 회차. 공개 기간·노출 on/off는 공지와 같은 규칙이고, 커뮤니티 상단
  배너 이미지와 빙고 배치(스탬프 종류 id 25개, JSONB)를 갖는다.
- running_week_participations: 참가 신청. (회차, 사용자)당 하나. 이름·연락처 등
  개인정보라 expires_at(신청 + 1년)이 지나면 서버가 지운다.

새 테이블만 만들므로 옛 코드에 무해하다.

Revision ID: 0031_running_weeks
Revises: 0030_stamp_definitions
Create Date: 2026-10-18 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0031_running_weeks"
down_revision: Union[str, Sequence[str], None] = "0030_stamp_definitions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "running_weeks",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "bingo_stamp_ids", JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )

    op.create_table(
        "running_week_participations",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "running_week_id",
            UUID(as_uuid=True),
            sa.ForeignKey("running_weeks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column("name", sa.String(50), nullable=False),
        sa.Column("phone", sa.String(20), nullable=False),
        sa.Column("gender", sa.String(10), nullable=False),
        sa.Column("age", sa.SmallInteger(), nullable=False),
        sa.Column("residence", sa.String(20), nullable=False),
        sa.Column("form_version", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("agreed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint(
            "running_week_id", "user_id", name="uq_running_week_participation_user"
        ),
    )
    op.create_index(
        "ix_running_week_participations_running_week_id",
        "running_week_participations",
        ["running_week_id"],
    )
    op.create_index(
        "ix_running_week_participations_user_id", "running_week_participations", ["user_id"]
    )
    op.create_index(
        "ix_running_week_participations_expires_at",
        "running_week_participations",
        ["expires_at"],
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("running_week_participations")
    op.drop_table("running_weeks")
