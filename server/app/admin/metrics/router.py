"""지표 HTTP — 목록 / 단일 / 묶음 조회. (관리자 전용 — admin_router가 가드)

GET /admin/metrics                      지표 목록(이름·표시명·지원 group_by)
GET /admin/metrics/batch?names=a,b      여러 지표를 한 번에 {name: [point]}
GET /admin/metrics/retention            가입 주별 재방문율
GET /admin/metrics/screens              화면별 PV·체류시간
GET /admin/metrics/{name}               지표 하나 [point]

point는 {key, name, count}다. group_by=none이면 key가 null인 한 줄, day면 key가
날짜(빈 날은 0으로 채움), course면 key가 코스 id이고 name에 코스명이 붙는다.
기간(from/to)은 KST 날짜, 양끝 포함. 생략하면 day는 최근 30일, 나머지는 전체 기간.
"""

import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import distinct, func, select
from sqlalchemy.orm import Session

from app.admin.metrics import sources
from app.admin.metrics.registry import METRICS, Metric
from app.db import get_db
from app.models import Course, User, UserLog
from app.routers.courses import KST
from app.schemas import MetricInfoOut, MetricPointOut, RetentionCohortOut, ScreenStatOut

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


# 재방문을 보는 날 수. 'n일 리텐션' = 가입 다음 날부터 n일째까지 사이에 하루라도 앱을 쓴 비율.
RETENTION_DAYS = (1, 7, 30)


@router.get("/metrics/retention", response_model=list[RetentionCohortOut])
def retention(
    weeks: int = Query(default=8, ge=1, le=26),
    db: Session = Depends(get_db),
):
    """최근 weeks주의 가입 주(KST 월요일 시작)별 재방문율. 최신 주가 먼저.

    가입 당일 활동은 재방문이 아니다. 코호트의 마지막 가입자에게 아직 n일이 다 지나지
    않았으면 그 칸은 null — 비율이 낮게 보이는 걸 막는다. 탈퇴자도 가입자 수에 든다.
    """
    today = datetime.now(KST).date()
    first = today - timedelta(days=today.weekday(), weeks=weeks - 1)
    since = datetime.combine(first, time.min, KST)

    signups = db.execute(
        select(User.id, sources.kst_date(User.created_at).label("day"))
        .where(User.created_at >= since)
    ).all()
    if not signups:
        return []

    day = sources.kst_date(UserLog.created_at)
    visits = db.execute(
        select(UserLog.user_id, day.label("day"))
        .where(UserLog.user_id.in_([str(u.id) for u in signups]), UserLog.created_at >= since)
        .group_by(UserLog.user_id, day)
    ).all()
    visited: dict[str, set[date]] = defaultdict(set)
    for user_id, visit_day in visits:
        visited[user_id].add(visit_day)

    cohorts: dict[date, dict] = {}
    for user_id, signup_day in signups:
        monday = signup_day - timedelta(days=signup_day.weekday())
        cohort = cohorts.setdefault(
            monday, {"signups": 0, "last": signup_day, **{n: 0 for n in RETENTION_DAYS}}
        )
        cohort["signups"] += 1
        cohort["last"] = max(cohort["last"], signup_day)
        gaps = {(d - signup_day).days for d in visited.get(str(user_id), ())}
        for n in RETENTION_DAYS:
            if any(1 <= gap <= n for gap in gaps):
                cohort[n] += 1

    return [
        {
            "week_start": monday,
            "signups": c["signups"],
            "returned": {
                str(n): c[n] if (today - c["last"]).days >= n else None for n in RETENTION_DAYS
            },
        }
        for monday, c in sorted(cohorts.items(), reverse=True)
    ]


@router.get("/metrics/screens", response_model=list[ScreenStatOut])
def screen_stats(
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    db: Session = Depends(get_db),
):
    """화면별 조회 수(PV)·고유 사용자·체류시간. 기간 생략 시 최근 30일, PV 많은 순.

    체류시간은 screen_view에서 같은 세션의 다음 screen_view·app_background까지다.
    뒤따르는 로그가 없는 조회(화면을 보다 앱이 죽음)는 PV에만 들고 체류시간에서 빠진다.
    """
    start, end = resolve_period(start, end, "day")
    events = (
        select(
            UserLog.log_name,
            UserLog.user_id,
            UserLog.detail["screen"].astext.label("screen"),
            UserLog.created_at,
            func.lead(UserLog.created_at)
            .over(partition_by=UserLog.session_id, order_by=(UserLog.created_at, UserLog.id))
            .label("next_at"),
        )
        .where(
            UserLog.log_name.in_(("screen_view", "app_background")),
            UserLog.session_id.is_not(None),
            *sources.Period(start, end).clauses(UserLog.created_at),
        )
        .subquery()
    )
    dwell = func.extract("epoch", events.c.next_at - events.c.created_at)
    rows = db.execute(
        select(
            events.c.screen,
            func.count().label("views"),
            func.count(distinct(events.c.user_id)).label("users"),
            func.avg(dwell).label("avg_sec"),
            func.percentile_cont(0.5).within_group(dwell).label("median_sec"),
            func.coalesce(func.sum(dwell), 0).label("total_sec"),
        )
        .where(events.c.log_name == "screen_view", events.c.screen.is_not(None))
        .group_by(events.c.screen)
        .order_by(func.count().desc(), events.c.screen)
    ).all()
    return [
        {
            "screen": r.screen,
            "views": r.views,
            "users": r.users,
            "avg_sec": None if r.avg_sec is None else round(float(r.avg_sec), 1),
            "median_sec": None if r.median_sec is None else round(float(r.median_sec), 1),
            "total_sec": round(float(r.total_sec)),
        }
        for r in rows
    ]


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
