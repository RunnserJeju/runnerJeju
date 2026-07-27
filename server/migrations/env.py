"""Alembic 실행 환경.

접속 정보는 alembic.ini가 아니라 app.db의 DATABASE_URL을 그대로 쓴다.
서버와 마이그레이션이 서로 다른 DB를 보는 사고를 막기 위해서다.
"""

from logging.config import fileConfig

from alembic import context

from app.db import DATABASE_URL, Base, engine

# models를 import해야 Base.metadata에 테이블이 등록된다(autogenerate에 필요).
from app import models  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def include_object(obj, name, type_, reflected, compare_to) -> bool:
    """autogenerate가 볼 대상을 우리 테이블로 한정한다.

    DB 이미지가 PostGIS라서 topology, layer, spatial_ref_sys, county_lookup 등
    확장이 만든 테이블이 함께 들어 있다. 이걸 걸러내지 않으면 autogenerate가
    "메타데이터에 없는 테이블"로 보고 전부 DROP하는 마이그레이션을 만들어낸다.
    """
    if type_ == "table" and reflected and name not in target_metadata.tables:
        return False
    return True


def run_migrations_offline() -> None:
    """DB에 붙지 않고 SQL만 출력한다 (alembic upgrade head --sql)."""
    context.configure(
        url=DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            include_object=include_object,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
