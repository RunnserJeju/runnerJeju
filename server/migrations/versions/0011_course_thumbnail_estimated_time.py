"""courses에 estimated_time_min / thumbnail_url 컬럼 추가

코스 관리에서 예상 소요시간(분)과 대표 썸네일을 다루기 위한 컬럼이다.

이름이 낯익다면 맞다 — 0008에서 걷어냈던 estimated_duration_sec / thumbnail_url을
다시 들인다. 다만 소요시간은 초가 아니라 **분**(안내용이라 분 단위로 충분하고
관리 화면 입력이 자연스럽다), 썸네일은 배너와 같은 Supabase Storage public URL이다
(app.storage). 실제 파일 업로드/교체/삭제는 전용 엔드포인트가 맡고, 이 컬럼은
그 결과 URL만 담는다.

**둘 다 nullable이라 server_default가 필요 없다.** 기존 코스(21개)는 값이 없어도
되는 항목이라 NULL로 남긴다 — 0008이 tags/parking_address 같은 nullable 컬럼을
default 없이 add_column한 것과 같은 방식이다. NOT NULL이 아니므로 기존 행을
채워 넣을 일도, TRUNCATE도 없다.

Revision ID: 0011_course_thumbnail_estimated_time
Revises: 0010_favorites
Create Date: 2026-08-30 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0011_course_thumbnail_estimated_time"
down_revision: Union[str, Sequence[str], None] = "0010_favorites"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# 예상 소요시간(분)과 썸네일 public URL. 둘 다 명단에 없을 수 있어 nullable이다.
ADDED = (
    ("estimated_time_min", sa.Integer()),
    ("thumbnail_url", sa.String(500)),
)


def upgrade() -> None:
    """Upgrade schema."""
    for name, type_ in ADDED:
        op.add_column("courses", sa.Column(name, type_, nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    for name, _type in ADDED:
        op.drop_column("courses", name)
