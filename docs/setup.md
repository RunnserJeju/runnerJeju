# 환경설정

로컬에서 서버 + DB를 붙여서 개발할 수 있는 환경을 만드는 절차.

## 사전 준비

- Docker
- [uv](https://docs.astral.sh/uv/) (`brew install uv`)

## 1. DB 실행 (PostGIS)

```bash
docker compose -f infra/docker-compose.yml up -d
```

## 2. 서버 의존성 설치

```bash
cd server
uv sync
```

`uv.lock`에 고정된 버전 그대로 `.venv`가 만들어진다. `DATABASE_URL` 환경변수로 접속 정보를 바꿀 수 있고, 기본값은 위 docker-compose 계정과 일치한다 ([db.py](server/app/db.py)).

## 3. 서버 실행

```bash
uv run uvicorn app.main:app --reload --port 8000
```

## 확인

```bash
curl http://localhost:8000/health
```

```json
{"status": "ok", "db": "connected"}
```

이 응답이 나오면 서버 -> DB 연결까지 정상.
