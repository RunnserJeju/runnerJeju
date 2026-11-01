"""시나리오 테스트 환경: 진짜 Postgres를 Docker로 띄우고, 마이그레이션을 돌리고, 끝나면 지운다.

팀 공유 DB에는 붙지 않는다 — 컨테이너 주소를 직접 만들어 쓰고 DATABASE_URL 환경변수는 읽지 않는다.
앱의 DB 주소는 app.db가 import 시점에 고정해 버리므로, 마이그레이션은 별도 프로세스로 돌리고
테스트는 자체 연결(engine)을 쓴다. 시나리오가 부르는 함수는 모두 Session을 인자로 받는다.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

SERVER_DIR = Path(__file__).resolve().parents[2]
# 운영·로컬 개발과 같은 이미지(infra/docker-compose.yml). PostGIS 확장이 필요한 마이그레이션이 있을 수 있다.
POSTGRES_IMAGE = "postgis/postgis:16-3.4"

# 시나리오마다 비우는 테이블. 쿠폰 종류(coupons)는 마이그레이션이 심은 행을 쓰므로 남긴다.
_RESET_TABLES = (
    "coupon_draws, user_coupons, stamps, stamp_definitions, verifications, runs, "
    "running_week_participations, running_weeks, courses"
)


def pytest_addoption(parser):
    parser.addoption("--open-report", action="store_true", help="시나리오 리포트를 끝나자마자 브라우저로 연다")


def pytest_terminal_summary(terminalreporter, config):
    """시나리오를 돌렸으면 HTML 리포트를 만들고 위치를 알려 준다."""
    from scenario_report import write_report
    from scenario_runner import RESULTS

    if not RESULTS:
        return
    path = write_report(RESULTS)
    terminalreporter.write_sep("-", "시나리오 리포트")
    terminalreporter.write_line(str(path))
    if config.getoption("--open-report"):
        import webbrowser

        webbrowser.open(path.as_uri())


def pytest_collection_modifyitems(items):
    """이 폴더의 테스트는 전부 scenario 표시를 단다 — 평소 pytest에서는 빠진다."""
    for item in items:
        if Path(str(item.fspath)).parent == Path(__file__).parent:
            item.add_marker(pytest.mark.scenario)


@pytest.fixture(scope="session")
def database_url():
    from testcontainers.community.postgres import PostgresContainer

    with PostgresContainer(
        POSTGRES_IMAGE, username="runner", password="runner", dbname="runner_test", driver="psycopg"
    ) as postgres:
        url = postgres.get_connection_url()
        migrate = subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=SERVER_DIR,
            env={**os.environ, "DATABASE_URL": url},
            capture_output=True,
            text=True,
        )
        if migrate.returncode != 0:
            pytest.exit(f"마이그레이션 실패:\n{migrate.stderr[-3000:]}", returncode=2)
        yield url


@pytest.fixture(scope="session")
def engine(database_url):
    engine = create_engine(database_url)
    yield engine
    engine.dispose()


@pytest.fixture
def db(engine):
    with engine.begin() as connection:
        connection.execute(text(f"TRUNCATE {_RESET_TABLES} RESTART IDENTITY CASCADE"))
    with Session(engine) as session:
        yield session
