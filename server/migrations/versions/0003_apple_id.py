"""apple_id

Revision ID: 0003_apple_id
Revises: c22aea43b744
Create Date: 2026-08-02 00:00:00.000000

이 마이그레이션은 Supabase DB에 이미 적용되어 있던 스키마 변경을 뒤늦게 파일로
남긴 것이다 (실제 ALTER는 다른 작업자가 DB에 직접 실행했고, 마이그레이션 파일과
models.py 반영이 누락되어 있었다). upgrade()는 그 상태를 그대로 재현한다.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0003_apple_id'
down_revision: Union[str, Sequence[str], None] = 'c22aea43b744'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('users', sa.Column('apple_id', sa.String(length=100), nullable=True))
    op.create_index(op.f('ix_users_apple_id'), 'users', ['apple_id'], unique=True)
    op.alter_column('users', 'kakao_id', existing_type=sa.String(length=100), nullable=True)


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('users', 'kakao_id', existing_type=sa.String(length=100), nullable=False)
    op.drop_index(op.f('ix_users_apple_id'), table_name='users')
    op.drop_column('users', 'apple_id')
