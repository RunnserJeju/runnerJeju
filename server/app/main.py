from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app import schema_guard
from app.db import engine
from app.routers import auth, banners, courses, notices, runs, stamps, verifications


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 스키마는 Alembic이 관리한다(예전의 create_all은 컬럼 변경을 반영하지 못해
    # 모델과 DB가 조용히 어긋났다). 도커 엔트리포인트가 기동 전에 upgrade를
    # 실행하지만, 그 경로를 우회해 띄웠을 때를 대비해 여기서 한 번 더 확인한다.
    schema_guard.verify(engine)
    yield


app = FastAPI(title="Runners Jeju API", lifespan=lifespan)

# 로컬 개발 단계: Flutter web(dev server)에서 오는 요청을 허용한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(banners.router)
app.include_router(courses.router)
app.include_router(runs.router)
app.include_router(verifications.router)
app.include_router(stamps.router)
app.include_router(notices.router)


@app.get("/ping")
def ping():
    return {"message": "pong"}


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok", "db": "connected"}
