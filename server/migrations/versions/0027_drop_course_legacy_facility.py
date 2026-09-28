"""courses의 옛 단일 주소 컬럼(parking_address/restroom_address) 삭제

0009에서 parkings/restrooms(JSONB)를 추가하며 "코드가 넘어가면 지운다"고 미뤄둔
정리다(원래 0010 예정이었으나 그 번호는 favorites가 썼다). 이제 쓰는 곳도 읽는 곳도
없다 — 등록 경로는 모두 JSONB에만 쓰고, 앱 화면도 parkings/restrooms를 읽는다.

**컬럼을 읽지 않는 서버 코드가 먼저 배포된 뒤에 적용해야 한다.** CI는 마이그레이션을
돌린 다음 새 리비전으로 트래픽을 넘기므로, 같은 배포에 실으면 그 사이 옛 리비전이
없는 컬럼을 SELECT해 코스 API가 실패한다.

옛 컬럼에만 값이 있고 JSONB는 빈 코스가 있으면 지우는 순간 그 정보가 사라지므로,
그런 행이 하나라도 있으면 멈춘다. 그 경우 `python -m tools.backfill_course_facilities`로
옛 주소를 좌표와 함께 parkings/restrooms로 옮긴 뒤 다시 돌린다(개발 DB가 실제로 그랬다 —
코스 14개가 옛 컬럼에만 주차장/화장실을 갖고 있었다).

downgrade는 컬럼만 되살린다(값은 복구되지 않는다).

Revision ID: 0027_drop_course_legacy_facility
Revises: 0026_course_partners
Create Date: 2026-09-28 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0027_drop_course_legacy_facility"
down_revision: Union[str, Sequence[str], None] = "0026_course_partners"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (옛 컬럼, 대체한 JSONB 컬럼)
DROPPED = (("parking_address", "parkings"), ("restroom_address", "restrooms"))


def upgrade() -> None:
    """Upgrade schema."""
    conn = op.get_bind()
    for old, new in DROPPED:
        orphaned = conn.execute(
            sa.text(
                f"SELECT name FROM courses "
                f"WHERE {old} IS NOT NULL AND {new} = '[]'::jsonb"
            )
        ).scalars().all()
        if orphaned:
            raise RuntimeError(
                f"{old}에만 값이 있는 코스가 있어 지우지 않는다 — "
                f"tools.backfill_course_facilities로 {new}에 먼저 옮길 것: "
                + ", ".join(orphaned)
            )

    for old, _ in DROPPED:
        op.drop_column("courses", old)


def downgrade() -> None:
    """Downgrade schema."""
    for old, _ in DROPPED:
        op.add_column("courses", sa.Column(old, sa.String(300), nullable=True))
