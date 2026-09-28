"""협력업체(partners) 테이블과 코스 연결(course_partners) 테이블 추가

협력업체는 운영 웹에서 따로 관리하는 리소스다. 주차장/화장실(courses JSONB)처럼
코스마다 복사해 두지 않는 이유는, 한 업체가 여러 코스에 걸리고 업체 정보를 고치면
연결된 모든 코스에 바로 반영돼야 하기 때문이다.

- partners: 이름·좌표 필수, 주소·코멘트·인스타그램·혜택 선택, detail(JSONB)은
  아직 형태가 정해지지 않은 부가 정보 자리다.
- course_partners: (course_id, partner_id) 복합 PK + 표시 순서. 코스나 업체가
  지워지면 연결도 CASCADE로 지워진다.

새 테이블만 만들므로 옛 코드에 무해하다.

Revision ID: 0026_course_partners
Revises: 0025_course_distance_decimal
Create Date: 2026-09-28 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0026_course_partners"
down_revision: Union[str, Sequence[str], None] = "0025_course_distance_decimal"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "partners",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("address", sa.String(300), nullable=True),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lng", sa.Float(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("instagram", sa.String(200), nullable=True),
        sa.Column("benefit", sa.String(500), nullable=True),
        sa.Column(
            "detail",
            JSONB,
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    op.create_table(
        "course_partners",
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "partner_id",
            UUID(as_uuid=True),
            sa.ForeignKey("partners.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    # 복합 PK(course_id, partner_id)로는 "이 업체가 걸린 코스"를 인덱스로 못 찾는다.
    op.create_index(
        "ix_course_partners_partner_id", "course_partners", ["partner_id"]
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_course_partners_partner_id", table_name="course_partners")
    op.drop_table("course_partners")
    op.drop_table("partners")
