from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.db import Base, engine
from app.routers import auth, courses, runs, stamps, verifications

# models를 import해야 Base.metadata에 테이블이 등록된다.
from app import models  # noqa: F401


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 초기 개발 단계라 기동 시 테이블을 만든다.
    # 스키마가 굳으면 Alembic 마이그레이션으로 옮겨야 한다 —
    # create_all은 기존 테이블의 컬럼 변경을 반영하지 못한다.
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Runner Jeju API", lifespan=lifespan)

# 로컬 개발 단계: Flutter web(dev server)에서 오는 요청을 허용한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(courses.router)
app.include_router(runs.router)
app.include_router(verifications.router)
app.include_router(stamps.router)


@app.get("/ping")
def ping():
    return {"message": "pong"}


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok", "db": "connected"}
