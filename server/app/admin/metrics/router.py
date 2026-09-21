"""지표 HTTP — 목록 / 단일 / 묶음 조회. (관리자 전용 — admin_router가 가드)

GET /admin/metrics                      지표 목록(이름·표시명·지원 group_by)
GET /admin/metrics/batch?names=a,b      여러 지표를 한 번에 {name: [point]}
GET /admin/metrics/{name}               지표 하나 [point]

point는 {key, name, count}다. group_by=none이면 key가 null인 한 줄, day면 key가
날짜(빈 날은 0으로 채움), course면 key가 코스 id이고 name에 코스명이 붙는다.
기간(from/to)은 KST 날짜, 양끝 포함. 생략하면 day는 최근 30일, 나머지는 전체 기간.
"""

import uuid
from datetime import date, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.admin.metrics import sources
from app.admin.metrics.registry import METRICS, Metric
from app.db import get_db
from app.models import Course
from app.routers.courses import KST
from app.schemas import MetricInfoOut, MetricPointOut

router = APIRouter(tags=["metrics"])

GroupBy = Literal["none", "day", "course"]
DEFAULT_DAYS = 30


def resolve_period(start: date | None, end: date | None, group_by: str) -> tuple[date | None, date]:
    """기간 기본값. end 없으면 오늘, start 없으면 day는 최근 30일·그 외는 전체."""
    end = end or datetime.now(KST).date()
    if start is None and group_by == "day":
        start = end - timedelta(days=DEFAULT_DAYS - 1)
    if start is not None and start > end:
        raise HTTPException(status_code=422, detail="from이 to보다 늦어요.")
    return start, end


def get_metric(name: str, group_by: str) -> Metric:
    metric = METRICS.get(name)
    if metric is None:
        raise HTTPException(status_code=404, detail=f"알 수 없는 지표 '{name}'")
    if group_by not in metric.group_bys:
        raise HTTPException(
            status_code=422,
            detail=f"'{name}'은 group_by={group_by}를 지원하지 않아요 ({', '.join(metric.group_bys)}).",
        )
    return metric


def fill_days(rows: list[tuple[object, int]], start: date, end: date) -> list[dict]:
    counts = {key: count for key, count in rows}
    return [
        {"key": str(day), "name": None, "count": counts.get(day, 0)}
        for day in (start + timedelta(days=i) for i in range((end - start).days + 1))
    ]


def attach_course_names(db: Session, rows: list[tuple[object, int]]) -> list[dict]:
    """코스별 결과에 코스명을 붙인다(한 번의 IN 조회). 삭제된 코스는 name이 null."""
    counts: dict[uuid.UUID, int] = {}
    for key, count in rows:
        course_id = sources.course_key(key)
        if course_id is not None:
            counts[course_id] = counts.get(course_id, 0) + count
    names = dict(
        db.execute(select(Course.id, Course.name).where(Course.id.in_(counts))).all()
    ) if counts else {}
    points = [
        {"key": str(course_id), "name": names.get(course_id), "count": count}
        for course_id, count in counts.items()
    ]
    points.sort(key=lambda p: (-p["count"], p["name"] or "", p["key"]))
    return points


def evaluate(db: Session, metric: Metric, start: date | None, end: date, group_by: str) -> list[dict]:
    rows = metric.count(db, start, end, group_by)
    if group_by == "day":
        return fill_days(rows, start, end)
    if group_by == "course":
        return attach_course_names(db, rows)
    return [{"key": None, "name": None, "count": rows[0][1] if rows else 0}]


@router.get("/metrics", response_model=list[MetricInfoOut])
def list_metrics():
    return [
        {"name": m.name, "label": m.label, "group": m.group, "group_bys": list(m.group_bys)}
        for m in METRICS.values()
    ]


# /metrics/{name}보다 먼저 선언해야 'batch'가 지표 이름으로 잡히지 않는다.
@router.get("/metrics/batch", response_model=dict[str, list[MetricPointOut]])
def batch_metrics(
    names: str = Query(..., description="쉼표로 구분한 지표 이름"),
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    group_by: GroupBy = Query(default="none"),
    db: Session = Depends(get_db),
):
    requested = [n.strip() for n in names.split(",") if n.strip()]
    if not requested:
        raise HTTPException(status_code=422, detail="names가 비어 있어요.")
    metrics = [get_metric(n, group_by) for n in requested]
    start, end = resolve_period(start, end, group_by)
    return {m.name: evaluate(db, m, start, end, group_by) for m in metrics}


@router.get("/metrics/{name}", response_model=list[MetricPointOut])
def get_metric_points(
    name: str,
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    group_by: GroupBy = Query(default="none"),
    db: Session = Depends(get_db),
):
    metric = get_metric(name, group_by)
    start, end = resolve_period(start, end, group_by)
    return evaluate(db, metric, start, end, group_by)
