import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

# 기본값은 infra/docker-compose.yml 로컬 계정과 동일 — 직접 설치한 DB 등 다른 곳에 연결하려면 DATABASE_URL 환경변수로 덮어쓰면 됨
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://runner:runner@localhost:5432/runner_jeju"
)

# SQLAlchemy 엔진 생성 - 풀 개수나 타임아웃은 필요에 따라 추가 설정 가능
engine = create_engine(DATABASE_URL)
# SQLAlchemy 세션 생성
SessionLocal = sessionmaker(bind=engine)


class Base(DeclarativeBase):
    """모든 ORM 모델의 공통 베이스."""


def get_db():
    """요청 1개당 세션 1개. 라우터에서 Depends(get_db)로 주입받는다."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# 타입 힌트용 별칭
DbSession = Session
