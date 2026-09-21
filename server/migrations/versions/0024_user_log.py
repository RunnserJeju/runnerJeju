"""user_log 테이블 생성, course_views 편입 후 삭제

사용자 행동 로그를 한 테이블(user_log)에 모은다. 종류는 log_name, 부가 정보는
detail(JSONB). 옛 course_views 행은 log_name='course_detail_open',
detail={"course_id": ...}로 옮긴다 — 이미 하루 1회 중복제거된 데이터라 이관 구간의
raw 클릭 수는 고유 조회 수와 같다(도입일 이후부터 갈라진다).

Revision ID: 0024_user_log
Revises: 0023_apple_refresh_token
Create Date: 2026-09-19 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0024_user_log"
down_revision: Union[str, Sequence[str], None] = "0023_apple_refresh_token"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "user_log",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.String(100), nullable=True),
        sa.Column("session_id", sa.String(36), nullable=True),
        sa.Column("log_name", sa.String(50), nullable=False),
        sa.Column(
            "detail", JSONB(), server_default=sa.text("'{}'::jsonb"), nullable=False
        ),
        sa.Column("platform", sa.String(10), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_user_log_name_created", "user_log", ["log_name", "created_at"])
    op.create_index("ix_user_log_user_created", "user_log", ["user_id", "created_at"])
    op.create_index("ix_user_log_session", "user_log", ["session_id"])

    # course_views 이관. id는 그대로 재사용한다(둘 다 uuid4).
    op.execute(
        """
        INSERT INTO user_log (id, user_id, log_name, detail, created_at)
        SELECT id, user_id, 'course_detail_open',
               jsonb_build_object('course_id', course_id::text), created_at
        FROM course_views
        """
    )
    op.drop_table("course_views")


def downgrade() -> None:
    """Downgrade schema. 조회 로그를 하루 1회로 다시 접어 course_views로 되돌린다."""
    op.create_table(
        "course_views",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("course_id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column("view_date", sa.Date(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["course_id"], ["courses.id"]),
        sa.UniqueConstraint(
            "course_id", "user_id", "view_date", name="uq_course_view_user_day"
        ),
    )
    op.execute(
        """
        INSERT INTO course_views (id, course_id, user_id, view_date, created_at)
        SELECT DISTINCT ON (course_id, user_id, view_date)
               id, course_id, user_id, view_date, created_at
        FROM (
            SELECT id, (detail->>'course_id')::uuid AS course_id, user_id,
                   (created_at AT TIME ZONE 'Asia/Seoul')::date AS view_date, created_at
            FROM user_log
            WHERE log_name = 'course_detail_open'
              AND user_id IS NOT NULL
              AND (detail->>'course_id') IS NOT NULL
        ) v
        WHERE EXISTS (SELECT 1 FROM courses c WHERE c.id = v.course_id)
        ORDER BY course_id, user_id, view_date, created_at
        """
    )
    op.drop_index("ix_user_log_session", table_name="user_log")
    op.drop_index("ix_user_log_user_created", table_name="user_log")
    op.drop_index("ix_user_log_name_created", table_name="user_log")
    op.drop_table("user_log")
