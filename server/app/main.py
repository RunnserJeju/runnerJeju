from fastapi import FastAPI
from sqlalchemy import text

from app.db import engine

app = FastAPI(title="Runner Jeju API")


@app.get("/ping")
def ping():
    return {"message": "pong"}


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok", "db": "connected"}
