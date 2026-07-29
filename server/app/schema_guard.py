"""DB 스키마가 최신 마이그레이션까지 올라와 있는지 검사한다.

도커로 띄우면 엔트리포인트가 `alembic upgrade head`를 먼저 실행하므로 이 검사는
항상 통과한다. 문제는 그 경로를 우회했을 때다 — 로컬에서 `uv run uvicorn`으로
직접 띄우거나, 마이그레이션을 새로 추가하고 적용을 잊은 경우.

그때 서버가 그냥 뜨면 "코스 목록이 500을 뱉는데 코드는 멀쩡해 보이는" 상태가 된다.
어긋난 채로 뜨느니 기동을 거부하고 무엇을 해야 하는지 알려주는 편이 낫다.
"""

from pathlib import Path

from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy.engine import Engine

ALEMBIC_INI = Path(__file__).resolve().parent.parent / "alembic.ini"


class SchemaOutOfDateError(RuntimeError):
    """DB 리비전이 head가 아닐 때."""


def expected_revision() -> str | None:
    """마이그레이션 파일들이 가리키는 최신 리비전."""
    return ScriptDirectory.from_config(Config(str(ALEMBIC_INI))).get_current_head()


def actual_revision(engine: Engine) -> str | None:
    """DB의 alembic_version에 기록된 리비전. 한 번도 적용 안 했으면 None."""
    with engine.connect() as connection:
        return MigrationContext.configure(connection).get_current_revision()


def verify(engine: Engine) -> None:
    """스키마가 최신이 아니면 SchemaOutOfDateError."""
    expected = expected_revision()
    actual = actual_revision(engine)

    if actual == expected:
        return

    where = "아직 한 번도 적용되지 않았어요" if actual is None else f"현재 {actual}"

    raise SchemaOutOfDateError(
        f"DB 스키마가 최신이 아니에요 ({where}, 필요한 리비전 {expected}). "
        "`uv run alembic upgrade head`를 실행한 뒤 다시 띄워주세요. "
        "도커로 띄우면 엔트리포인트가 자동으로 처리합니다."
    )
