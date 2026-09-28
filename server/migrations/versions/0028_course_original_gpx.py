"""courses.original_gpx 추가 — 업로드한 GPX 원본 바이트

path는 등록 시 15m 간격으로 리샘플한 경로라 원본 점이 남지 않는다(중간 꼭짓점은
버려지고 사이 점은 보간된다). 판정·지도는 계속 path를 쓰고, 원본은 여기 따로
보관해 사용자가 GPX로 내려받을 수 있게 한다(GET /courses/{id}/gpx).

점 목록이 아니라 파일 바이트를 그대로 둔다 — 이름·시각·트랙 구분 같은 파싱이
버리는 정보까지 올린 그대로 돌려주려는 것이고, 인코딩 선언이 UTF-8이 아닌 파일도
있어 텍스트로 바꾸지 않는다.

nullable이다. 이 컬럼 전에 올라간 코스는 NULL로 시작하고, 적용 뒤
tools/backfill_course_original_gpx로 채운다(레포 GPX가 있으면 그 파일, 없으면
리샘플 경로로 지은 GPX).

Revision ID: 0028_course_original_gpx
Revises: 0027_drop_course_legacy_facility
Create Date: 2026-09-28 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0028_course_original_gpx"
down_revision: Union[str, Sequence[str], None] = "0027_drop_course_legacy_facility"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("courses", sa.Column("original_gpx", sa.LargeBinary(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("courses", "original_gpx")
