"""courses에 parkings/restrooms JSONB 컬럼 추가

주차장/화장실을 코스당 여러 개 저장하기 위한 컬럼이다. 각 원소는
{"name": str|null, "address": str, "lat": float, "lng": float} 형태로,
등록 시점에 주소를 좌표로 변환(app/geocoding.py)해 넣는다. path와 같은
JSONB 전략이다(models.py 상단 주석 참고).

**옛 컬럼(parking_address/restroom_address)은 여기서 지우지 않는다.** 지금
모델·스키마·프론트가 아직 그 컬럼을 읽고 있어서, 지우면 배포 전 팀원 코드가
깨진다. 추가만 하는 이 마이그레이션은 옛 코드에 무해하다(새 컬럼을 안 읽으니).
옛 컬럼 drop은 코드가 새 컬럼으로 전환된 뒤 별도 마이그레이션(0010)으로 한다.

기존 행(코스 21개)이 있으므로 NOT NULL 컬럼엔 server_default('[]'::jsonb)를
붙여 채운다. path처럼 항상 리스트라 null은 두지 않는다.

Revision ID: 0009_course_facilities_jsonb
Revises: 0008_course_columns
Create Date: 2026-08-23 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0009_course_facilities_jsonb"
down_revision: Union[str, Sequence[str], None] = "0008_course_columns"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ADDED = ("parkings", "restrooms")


def upgrade() -> None:
    """Upgrade schema."""
    for name in ADDED:
        op.add_column(
            "courses",
            sa.Column(
                name,
                JSONB,
                nullable=False,
                server_default=sa.text("'[]'::jsonb"),
            ),
        )
        # 기본값은 기존 행을 채우기 위한 것일 뿐, 이후 삽입은 앱이 값을 준다.
        # 모델(default=list)과 역할이 겹치지 않게 DB 기본값은 떼어 둔다.
        op.alter_column("courses", name, server_default=None)


def downgrade() -> None:
    """Downgrade schema."""
    for name in ADDED:
        op.drop_column("courses", name)
