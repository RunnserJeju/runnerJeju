from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app import config_guard, schema_guard
from app.admin import admin_auth_router, admin_router
from app.db import engine
from app.routers import (
    auth,
    banners,
    courses,
    favorites,
    notices,
    runs,
    stamps,
    verifications,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # DB에 붙기 전에 본다 — 설정이 틀렸으면 연결 에러보다 이쪽을 먼저 보여주는 게 낫다.
    config_guard.verify()

    # 스키마는 Alembic이 관리한다(예전의 create_all은 컬럼 변경을 반영하지 못해
    # 모델과 DB가 조용히 어긋났다). 도커 엔트리포인트가 기동 전에 upgrade를
    # 실행하지만, 그 경로를 우회해 띄웠을 때를 대비해 여기서 한 번 더 확인한다.
    schema_guard.verify(engine)

    # 개발과 운영이 같은 이미지라 로그로 구분할 수단이 없으면 사고가 늦게 발견된다.
    print(f"▶ DB {config_guard.describe_database(engine)}", flush=True)
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
app.include_router(favorites.router)
app.include_router(runs.router)
app.include_router(verifications.router)
app.include_router(stamps.router)
app.include_router(notices.router)

# 운영자 전용. 로그인 라우터(admin_auth_router)는 가드 밖, 나머지(admin_router)는
# 라우터 레벨에서 require_admin_session으로 보호된다(app/admin/__init__.py).
app.include_router(admin_auth_router)
app.include_router(admin_router)

# 운영 웹(frontend/admin의 vite build 결과). 같은 오리진에서 서빙해 인증을 단순하게
# 유지한다(docs/admin-web.md "오리진 배치"). 빌드 산출물은 배포 파이프라인이
# 채운다(cloudbuild.yaml admin-build 스텝) — 로컬에 없으면 API만 뜬다.
_ADMIN_UI_DIR = Path(__file__).resolve().parent.parent / "static" / "admin"
if _ADMIN_UI_DIR.is_dir():
    app.mount("/admin-ui", StaticFiles(directory=_ADMIN_UI_DIR, html=True), name="admin-ui")


@app.get("/ping")
def ping():
    return {"message": "pong"}


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok", "db": "connected"}
