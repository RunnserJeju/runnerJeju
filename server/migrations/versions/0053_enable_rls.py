"""public 테이블 전부 RLS 켜기 (정책 없음)

Supabase는 public 테이블을 Data API로 공개한다. RLS가 꺼져 있으면 공개 키(anon)만으로
전부 읽고 쓸 수 있다(#132). 정책 없이 켜서 공개 키 쪽만 막는다 — 서버는 테이블 소유자로
접속하므로 영향이 없다. 이후 새 테이블을 만드는 마이그레이션도 RLS를 켜야 한다.

Revision ID: 0053_enable_rls
Revises: 0052_external_completions
Create Date: 2026-11-22 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0053_enable_rls"
down_revision: Union[str, Sequence[str], None] = "0052_external_completions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _set_rls(action: str) -> None:
    op.execute(
        f"""
        DO $$
        DECLARE t record;
        BEGIN
            FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
                EXECUTE format('ALTER TABLE public.%I {action} ROW LEVEL SECURITY', t.tablename);
            END LOOP;
        END $$;
        """
    )


def upgrade() -> None:
    """Upgrade schema."""
    _set_rls("ENABLE")


def downgrade() -> None:
    """Downgrade schema."""
    _set_rls("DISABLE")
