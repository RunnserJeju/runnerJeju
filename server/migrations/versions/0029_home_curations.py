"""앱 홈 구성 테이블 추가 — course_curations, partner_curations

앱 홈의 '러닝 코스 큐레이션'(코스)과 '추천 협력 업체'(업체)에 무엇을 어떤 순서로
띄울지 운영 웹 '홈 구성' 화면에서 고른다. 홈에 나오는 건 섹션마다 몇 개뿐이라
courses/partners에 대부분 비어 있을 컬럼을 붙이지 않고, 고른 것만 행으로 담는다.

- course_curations: course_id PK + 표시 순서. 코스가 지워지면 CASCADE로 빠진다.
- partner_curations: partner_id PK + 표시 순서. 업체가 지워지면 CASCADE로 빠진다.

둘 다 describe(운영자가 쓰는 큐레이션 설명)와 detail(JSONB, 형태 미정 부가 정보)을
갖는다. 앱에 어떻게 노출할지는 아직 정하지 않았고, 응답에는 실어 둔다.

새 테이블만 만들므로 옛 코드에 무해하다.

초기값은 이 전까지 앱 홈이 일반 사용자에게 보여주던 것 그대로 채운다 — 비워 두면
배포하는 순간 홈 두 섹션이 사라지고, 운영 웹 '홈 구성'도 빈 화면에서 시작한다.
  - 코스: 공개 코스 중 최신 등록순 5개(옛 '추천 코스' = GET /courses 앞 5개).
  - 업체: 공개 코스에 하나라도 연결된 업체 중 이름순 5곳(옛 '러닝 코스 큐레이션').

Revision ID: 0029_home_curations
Revises: 0028_course_original_gpx
Create Date: 2026-10-17 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0029_home_curations"
down_revision: Union[str, Sequence[str], None] = "0028_course_original_gpx"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _curation_extra_columns() -> list[sa.Column]:
    """두 큐레이션 테이블이 같이 갖는 설명·부가 정보 칸. 테이블마다 새 Column이 필요하다."""
    return [
        sa.Column("describe", sa.Text(), nullable=True),
        sa.Column(
            "detail",
            JSONB,
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
    ]


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "course_curations",
        sa.Column(
            "course_id",
            UUID(as_uuid=True),
            sa.ForeignKey("courses.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        *_curation_extra_columns(),
    )
    op.create_table(
        "partner_curations",
        sa.Column(
            "partner_id",
            UUID(as_uuid=True),
            sa.ForeignKey("partners.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        *_curation_extra_columns(),
    )

    # 초기값: 옛 홈이 보여주던 것(모듈 docstring 참고). 순서는 0부터.
    op.execute(
        """
        INSERT INTO course_curations (course_id, sort_order)
        SELECT id, (row_number() OVER (ORDER BY created_at DESC))::int - 1
        FROM courses
        WHERE visibility = 'public'
        ORDER BY created_at DESC
        LIMIT 5
        """
    )
    op.execute(
        """
        INSERT INTO partner_curations (partner_id, sort_order)
        SELECT p.id, (row_number() OVER (ORDER BY p.name))::int - 1
        FROM partners p
        WHERE EXISTS (
            SELECT 1
            FROM course_partners cp
            JOIN courses c ON c.id = cp.course_id
            WHERE cp.partner_id = p.id AND c.visibility = 'public'
        )
        ORDER BY p.name
        LIMIT 5
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("partner_curations")
    op.drop_table("course_curations")
