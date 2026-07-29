"""courses에 slug / is_loop / updated_at 추가

slug는 코스의 안정적인 식별자다. 같은 GPX를 다시 올렸을 때 새 코스를 만들지 않고
기존 코스를 갱신하기 위한 기준이며, 재업로드가 갱신이어야 하는 이유는 코스를
지웠다 다시 만들면 stamps.course_id가 가리키던 완주 스탬프가 고아가 되기 때문이다.

기존 행이 있어도 안전하게 올라가도록 nullable로 추가 → 백필 → NOT NULL 순으로 간다.

Revision ID: 0002_course_slug
Revises: 0001_baseline
"""

import sqlalchemy as sa
from alembic import op

revision = "0002_course_slug"
down_revision = "0001_baseline"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("courses", sa.Column("slug", sa.String(100), nullable=True))
    op.add_column(
        "courses",
        sa.Column("is_loop", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "courses",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    # 이미 있던 코스에는 id 앞자리로 임시 slug를 채운다. 사람이 읽을 만한 값은
    # 아니지만 유니크가 보장되고, 나중에 courses.yaml에서 제대로 된 slug로
    # 다시 올리면 갱신된다.
    op.execute(
        "UPDATE courses SET slug = 'course-' || substr(id::text, 1, 8) "
        "WHERE slug IS NULL"
    )

    op.alter_column("courses", "slug", nullable=False)
    op.create_index("ix_courses_slug", "courses", ["slug"], unique=True)

    # server_default는 백필용이었으므로 떼어낸다. 이후 값은 ORM이 채운다.
    op.alter_column("courses", "is_loop", server_default=None)


def downgrade() -> None:
    op.drop_index("ix_courses_slug", table_name="courses")
    op.drop_column("courses", "updated_at")
    op.drop_column("courses", "is_loop")
    op.drop_column("courses", "slug")
