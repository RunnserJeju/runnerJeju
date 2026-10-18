"""스탬프를 코스에서 분리 — stamp_definitions 추가 (#71)

스탬프가 코스에 1:1로 묶여 있던 구조(도안은 courses.stamp_image_url, 발급 기준은
(사용자, 코스))를, 도전과제처럼 "조건 종류 + 조건 값"을 가진 스탬프 종류로 바꾼다.
코스 완주는 조건 종류의 하나(course_complete {"course_id"})가 된다.

- stamp_definitions 생성.
- 코스마다 course_complete 스탬프를 하나씩 만든다. 이름은 코스 이름, 도안은
  courses.stamp_image_url을 옮긴다.
- stamps.stamp_definition_id를 채우고, 유일 조건을 (사용자, 스탬프 종류)로 바꾼 뒤
  stamps.course_id와 courses.stamp_image_url을 지운다.

downgrade는 course_complete 스탬프만 되돌린다. 그 밖의 종류(manual 등)로 받은
발급 기록은 돌아갈 코스가 없어 지워진다.

Revision ID: 0030_stamp_definitions
Revises: 0029_home_curations
Create Date: 2026-10-18 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0030_stamp_definitions"
down_revision: Union[str, Sequence[str], None] = "0029_home_curations"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "stamp_definitions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("condition_type", sa.String(30), nullable=False),
        sa.Column(
            "condition_params", JSONB, nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )

    # 코스마다 완주 스탬프 하나. 코스 등록 순서를 정렬 기본값으로 쓴다.
    op.execute(
        """
        INSERT INTO stamp_definitions (id, name, image_url, condition_type, condition_params, sort_order)
        SELECT gen_random_uuid(), left(c.name, 100), c.stamp_image_url, 'course_complete',
               jsonb_build_object('course_id', c.id::text),
               (row_number() OVER (ORDER BY c.created_at))::int
        FROM courses c
        """
    )

    op.add_column(
        "stamps",
        sa.Column("stamp_definition_id", UUID(as_uuid=True), nullable=True),
    )
    op.execute(
        """
        UPDATE stamps s SET stamp_definition_id = d.id
        FROM stamp_definitions d
        WHERE d.condition_type = 'course_complete'
          AND d.condition_params->>'course_id' = s.course_id::text
        """
    )
    op.alter_column("stamps", "stamp_definition_id", nullable=False)
    op.create_foreign_key(
        "fk_stamps_stamp_definition_id",
        "stamps",
        "stamp_definitions",
        ["stamp_definition_id"],
        ["id"],
    )
    op.create_index("ix_stamps_stamp_definition_id", "stamps", ["stamp_definition_id"])

    op.drop_constraint("uq_stamp_user_course", "stamps", type_="unique")
    op.create_unique_constraint(
        "uq_stamp_user_definition", "stamps", ["user_id", "stamp_definition_id"]
    )
    op.drop_index("ix_stamps_course_id", table_name="stamps")
    op.drop_column("stamps", "course_id")

    op.drop_column("courses", "stamp_image_url")


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column("courses", sa.Column("stamp_image_url", sa.String(500), nullable=True))
    op.execute(
        """
        UPDATE courses c SET stamp_image_url = d.image_url
        FROM stamp_definitions d
        WHERE d.condition_type = 'course_complete'
          AND d.condition_params->>'course_id' = c.id::text
        """
    )

    op.add_column(
        "stamps",
        sa.Column("course_id", UUID(as_uuid=True), sa.ForeignKey("courses.id"), nullable=True),
    )
    op.execute(
        """
        UPDATE stamps s SET course_id = (d.condition_params->>'course_id')::uuid
        FROM stamp_definitions d
        WHERE d.id = s.stamp_definition_id AND d.condition_type = 'course_complete'
        """
    )
    op.execute("DELETE FROM stamps WHERE course_id IS NULL")
    op.alter_column("stamps", "course_id", nullable=False)
    op.create_index("ix_stamps_course_id", "stamps", ["course_id"])

    op.drop_constraint("uq_stamp_user_definition", "stamps", type_="unique")
    op.create_unique_constraint("uq_stamp_user_course", "stamps", ["user_id", "course_id"])
    op.drop_index("ix_stamps_stamp_definition_id", table_name="stamps")
    op.drop_constraint("fk_stamps_stamp_definition_id", "stamps", type_="foreignkey")
    op.drop_column("stamps", "stamp_definition_id")

    op.drop_table("stamp_definitions")
