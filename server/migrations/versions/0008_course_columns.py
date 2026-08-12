"""courses 컬럼을 코스 명단 시트 기준으로 재정의

시트가 가진 컬럼(이름/거리/난이도/태그/주소/근처 주차장/근처 화장실)만 남기고
나머지를 걷어낸다. 없어지는 건 slug, region, distance_meters,
estimated_duration_sec, elevation_gain_meters, thumbnail_url, is_loop다.

기존 값을 옮기지 않는다. 코스는 시트를 기준으로 전부 새로 올릴 예정이라
백필할 대상이 애초에 없고, 거리는 Float(실측 m) → Integer(안내용 km),
난이도는 VARCHAR('easy') → SMALLINT(1)로 의미까지 바뀌어서 변환할 만한
대응 관계도 없다. 그래서 테이블을 비우고 컬럼을 갈아끼운다.

DROP TABLE + CREATE TABLE로 가지 않은 이유: runs / verifications / stamps
셋이 courses.id에 FK를 걸고 있다. DROP TABLE courses CASCADE는 테이블만
지우는 게 아니라 저 세 테이블의 FK 제약까지 같이 떼어내고, courses를 다시
만들어도 제약은 돌아오지 않는다. 비우고 ALTER하면 제약을 건드리지 않는다.
덤으로 테이블이 비어 있어서 NOT NULL 컬럼에 server_default를 붙였다 떼는
절차도 필요 없다.

Revision ID: 0008_course_columns
Revises: 0007_banners
Create Date: 2026-08-12 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0008_course_columns"
down_revision: Union[str, Sequence[str], None] = "0007_banners"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# 걷어내는 컬럼과, downgrade에서 되돌릴 정의.
DROPPED = (
    ("slug", sa.String(100)),
    ("region", sa.String(100)),
    ("distance_meters", sa.Float()),
    # 타입 변경(VARCHAR→SMALLINT) 대신 지우고 다시 만든다. 남길 값이 없으니
    # USING 절로 캐스팅할 이유가 없다.
    ("difficulty", sa.String(20)),
    ("estimated_duration_sec", sa.Integer()),
    ("elevation_gain_meters", sa.Float()),
    ("thumbnail_url", sa.String(500)),
    ("is_loop", sa.Boolean()),
)

ADDED = (
    # 왕복 기준 km. 시트에 적힌 안내값이라 실측 거리가 아니다.
    ("distance_km", sa.Integer(), False),
    # 1=★, 2=★★, 3=★★★
    ("difficulty", sa.SmallInteger(), False),
    # "해안도로,제주시,동쪽" 처럼 쉼표로 이어 붙인다.
    ("tags", sa.String(200), True),
    ("address", sa.String(300), False),
    ("parking_address", sa.String(300), True),
    ("restroom_address", sa.String(300), True),
)


def _truncate_courses_and_dependents() -> None:
    """courses와, courses를 참조하는 테이블을 함께 비운다.

    코스가 새 id로 다시 생기면 옛 course_id를 가리키던 러닝/검증/스탬프는
    가리킬 대상이 없다. TRUNCATE는 참조하는 테이블을 전부 같이 적어주면
    CASCADE 없이도 FK 검사를 통과한다.
    """
    op.execute("TRUNCATE verifications, stamps, runs, courses")


def upgrade() -> None:
    """Upgrade schema."""
    _truncate_courses_and_dependents()

    op.drop_index("ix_courses_slug", table_name="courses")
    op.drop_index("ix_courses_region", table_name="courses")

    for name, _type in DROPPED:
        op.drop_column("courses", name)

    for name, type_, nullable in ADDED:
        op.add_column("courses", sa.Column(name, type_, nullable=nullable))


def downgrade() -> None:
    """Downgrade schema.

    upgrade가 데이터를 버리는 마이그레이션이라 downgrade도 같다 — 새 스키마로
    쌓인 행을 옛 스키마(slug NOT NULL UNIQUE 등)로 되돌릴 방법이 없으므로
    컬럼 모양만 복구하고 내용은 버린다.
    """
    _truncate_courses_and_dependents()

    for name, _type, _nullable in ADDED:
        op.drop_column("courses", name)

    for name, type_ in DROPPED:
        op.add_column("courses", sa.Column(name, type_, nullable=False))

    op.create_index("ix_courses_region", "courses", ["region"])
    op.create_index("ix_courses_slug", "courses", ["slug"], unique=True)
