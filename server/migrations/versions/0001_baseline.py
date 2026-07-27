"""baseline: courses / runs / verifications / stamps

이 리비전은 Alembic 도입 이전에 `Base.metadata.create_all`로 만들어지던 스키마와
같은 결과를 낸다. 이미 create_all로 테이블이 만들어진 DB를 쓰고 있다면 다음처럼
이 리비전을 건너뛰고 합류하면 된다.

    alembic stamp 0001_baseline
    alembic upgrade head

Revision ID: 0001_baseline
Revises:
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "courses",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.String(2000), nullable=True),
        sa.Column("region", sa.String(100), nullable=True),
        sa.Column("difficulty", sa.String(20), nullable=False),
        sa.Column("distance_meters", sa.Float(), nullable=False),
        sa.Column("estimated_duration_sec", sa.Integer(), nullable=True),
        sa.Column("elevation_gain_meters", sa.Float(), nullable=True),
        sa.Column("thumbnail_url", sa.String(500), nullable=True),
        sa.Column("path", JSONB(), nullable=False),
        sa.Column("created_by", sa.String(100), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_courses_region", "courses", ["region"])

    op.create_table(
        "runs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id"),
            nullable=True,
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("distance_meters", sa.Float(), nullable=False),
        sa.Column("duration_sec", sa.Integer(), nullable=False),
        sa.Column("path", JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_runs_user_id", "runs", ["user_id"])
    op.create_index("ix_runs_course_id", "runs", ["course_id"])

    op.create_table(
        "verifications",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "run_id", UUID(as_uuid=True), sa.ForeignKey("runs.id"), nullable=False
        ),
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id"),
            nullable=False,
        ),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("match_rate", sa.Float(), nullable=True),
        sa.Column("detail", sa.String(500), nullable=True),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("run_id", "course_id", name="uq_verification_run_course"),
    )
    op.create_index("ix_verifications_run_id", "verifications", ["run_id"])
    op.create_index("ix_verifications_course_id", "verifications", ["course_id"])

    op.create_table(
        "stamps",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id"),
            nullable=False,
        ),
        sa.Column(
            "run_id", UUID(as_uuid=True), sa.ForeignKey("runs.id"), nullable=True
        ),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column(
            "acquired_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "course_id", name="uq_stamp_user_course"),
    )
    op.create_index("ix_stamps_user_id", "stamps", ["user_id"])
    op.create_index("ix_stamps_course_id", "stamps", ["course_id"])


def downgrade() -> None:
    op.drop_table("stamps")
    op.drop_table("verifications")
    op.drop_table("runs")
    op.drop_table("courses")
