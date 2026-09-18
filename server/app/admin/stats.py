"""운영자 전용 이용 통계 API — 전체 요약 + 코스별 지표.

완주(stamps)·찜(favorites)·러닝 이용자(runs)·가입/활성 회원(users)·조회수(course_views)를
집계한다. 조회수는 코스 상세 조회를 하루 1회 중복제거로 센 값이다(routers/courses의
_record_view). 일별 추이(/stats/daily)는 KST 날짜로 묶는다.

'미완주'는 course_id가 있는 러닝 중 검증(verifications)이 matched가 아닌 것이다 —
종료 버튼까지 눌러 업로드된 러닝만 세므로, 앱을 그냥 꺼서 업로드가 안 된 이탈은
여기 없다(앱에서 시작 이벤트를 보내야 잡힌다).

탈퇴(deleted_at) 취급:
- 가입/활성 회원 수는 탈퇴자를 뺀 '현재' 기준이다.
- 코스 완주/찜/이용자 누적은 탈퇴자를 포함한다(익명 보존, 역사적 누적) — 필터하지 않는다.
"""

import uuid
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import Date, String, cast, distinct, func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import (
    Course,
    CourseView,
    Favorite,
    Run,
    Stamp,
    User,
    UserCoupon,
    Verification,
)
from app.routers.courses import KST, _completed_counts
from app.schemas import (
    CourseStatsOut,
    DailyStatsOut,
    StampDistributionOut,
    StatsOverviewOut,
)

router = APIRouter(tags=["stats"])


def _favorite_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 찜 수를 한 번에 조회한다(목록에서 N+1을 피하려고)."""
    if not course_ids:
        return {}

    rows = db.execute(
        select(Favorite.course_id, func.count(Favorite.id))
        .where(Favorite.course_id.in_(course_ids))
        .group_by(Favorite.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


def _runner_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 '이용자 수'(그 코스를 달린 고유 사용자)를 한 번에 조회한다.

    완주자(스탬프)의 상위 집합이다 — 달렸지만 미완주인 사람도 포함. 탈퇴자의 러닝도
    익명 활동으로 남으므로 여기 포함된다(코스 지표는 역사적 누적).
    """
    if not course_ids:
        return {}

    rows = db.execute(
        select(Run.course_id, func.count(distinct(Run.user_id)))
        .where(Run.course_id.in_(course_ids))
        .group_by(Run.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


def _view_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 조회수(고유 조회 = course_views 행 수)를 한 번에 조회한다.

    course_views가 (course_id, user_id, view_date) 유니크라 하루 1회 중복제거된 행이다.
    그래서 raw 클릭 수가 아니라 '고유 조회(사람·일)' 합이다.
    """
    if not course_ids:
        return {}

    rows = db.execute(
        select(CourseView.course_id, func.count(CourseView.id))
        .where(CourseView.course_id.in_(course_ids))
        .group_by(CourseView.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


def _run_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 따라가기 러닝 횟수(고유 사용자가 아니라 건수)."""
    if not course_ids:
        return {}

    rows = db.execute(
        select(Run.course_id, func.count(Run.id))
        .where(Run.course_id.in_(course_ids))
        .group_by(Run.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


def _matched_counts(db: Session, course_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """코스별 검증 통과(matched) 건수. run_count - 이 값 = 미완주 러닝."""
    if not course_ids:
        return {}

    rows = db.execute(
        select(Verification.course_id, func.count(Verification.id))
        .where(
            Verification.course_id.in_(course_ids),
            Verification.status == "matched",
        )
        .group_by(Verification.course_id)
    ).all()

    return {course_id: count for course_id, count in rows}


@router.get("/stats/overview", response_model=StatsOverviewOut)
def stats_overview(db: Session = Depends(get_db)):
    """사이트 전체 요약. (관리자 전용 — 라우터 레벨에서 강제)

    registered_users/active_users는 탈퇴자를 제외한 '현재' 기준이고, 누적 활동
    (runs/completions/favorites)은 탈퇴자를 포함한 역사적 총계다.
    """
    registered_users = db.scalar(
        select(func.count()).select_from(User).where(User.deleted_at.is_(None))
    )
    # 실이용자 = 러닝 1회 이상 한 '현재(비탈퇴)' 고유 사용자. runs.user_id(String)를
    # users.id(UUID)와 맞추려 캐스트해 조인하고, 탈퇴 husk는 제외한다.
    active_users = db.scalar(
        select(func.count(distinct(Run.user_id)))
        .select_from(Run)
        .join(User, cast(User.id, String) == Run.user_id)
        .where(User.deleted_at.is_(None))
    )
    total_runs = db.scalar(select(func.count()).select_from(Run))
    total_completions = db.scalar(select(func.count()).select_from(Stamp))
    total_favorites = db.scalar(select(func.count()).select_from(Favorite))
    total_views = db.scalar(select(func.count()).select_from(CourseView))
    course_runs = db.scalar(
        select(func.count()).select_from(Run).where(Run.course_id.is_not(None))
    )
    matched_runs = db.scalar(
        select(func.count())
        .select_from(Verification)
        .where(Verification.status == "matched")
    )
    coupons_issued = db.scalar(select(func.count()).select_from(UserCoupon))
    coupons_used = db.scalar(
        select(func.count()).select_from(UserCoupon).where(UserCoupon.used_at.is_not(None))
    )

    return {
        "registered_users": registered_users,
        "active_users": active_users,
        "total_runs": total_runs,
        "total_completions": total_completions,
        "total_favorites": total_favorites,
        "total_views": total_views,
        "course_runs": course_runs,
        "incomplete_runs": max(course_runs - matched_runs, 0),
        "coupons_issued": coupons_issued,
        "coupons_used": coupons_used,
    }


@router.get("/stats/courses", response_model=list[CourseStatsOut])
def stats_courses(
    sort: Literal[
        "completions", "runners", "favorites", "views", "runs", "incomplete"
    ] = Query(default="completions"),
    db: Session = Depends(get_db),
):
    """코스별 지표(완주·찜·이용자)를 정렬해 반환. (관리자 전용)

    코스가 수십 개라 코스당 쿼리(N+1) 대신 지표를 배치 집계한 뒤 Python에서
    정렬한다 — 코스 1 + 완주·찜·이용자 각 group_by 1 = 쿼리 4개 고정. 정렬은
    내림차순(기본 완주순), 동점은 이름 오름차순. '인기 코스'가 곧 이 정렬이다.
    """
    # 지표만 필요하므로 무거운 JSONB(path/parkings/restrooms)까지 딸린 Course ORM을
    # 통째로 올리지 않고 필요한 3개 컬럼만 읽는다.
    rows = db.execute(select(Course.id, Course.name, Course.address)).all()
    course_ids = [row.id for row in rows]

    completions = _completed_counts(db, course_ids)
    favorites = _favorite_counts(db, course_ids)
    runners = _runner_counts(db, course_ids)
    views = _view_counts(db, course_ids)
    runs = _run_counts(db, course_ids)
    matched = _matched_counts(db, course_ids)

    items = [
        {
            "id": row.id,
            "name": row.name,
            "address": row.address,
            "completed_count": completions.get(row.id, 0),
            "favorite_count": favorites.get(row.id, 0),
            "runner_count": runners.get(row.id, 0),
            "view_count": views.get(row.id, 0),
            "run_count": runs.get(row.id, 0),
            "incomplete_run_count": max(
                runs.get(row.id, 0) - matched.get(row.id, 0), 0
            ),
        }
        for row in rows
    ]

    field = {
        "completions": "completed_count",
        "runners": "runner_count",
        "favorites": "favorite_count",
        "views": "view_count",
        "runs": "run_count",
        "incomplete": "incomplete_run_count",
    }[sort]
    # 내림차순(count) → 이름 오름차순 → id(동명·동점의 결정적 순서)
    items.sort(key=lambda x: (-x[field], x["name"], x["id"]))
    return items


def _kst_date(column):
    """timestamptz 컬럼을 KST 날짜로 바꾼다(일별 group_by 키)."""
    return cast(func.timezone("Asia/Seoul", column), Date)


def _daily_counts(db: Session, column, since: datetime, *filters) -> dict:
    """column(timestamptz)을 KST 날짜로 묶어 {date: count}로 돌려준다."""
    day = _kst_date(column)
    rows = db.execute(
        select(day, func.count()).where(column >= since, *filters).group_by(day)
    ).all()
    return {d: n for d, n in rows}


@router.get("/stats/daily", response_model=list[DailyStatsOut])
def stats_daily(
    days: int = Query(default=30, ge=1, le=365),
    db: Session = Depends(get_db),
):
    """최근 days일의 일별 활동 건수(KST). (관리자 전용)

    지표마다 group_by 한 번씩, 총 6쿼리 고정. 활동 없는 날은 0으로 채워 프론트가
    그대로 차트에 꽂을 수 있게 한다. 가입은 탈퇴한 husk도 포함한 '그날 가입한 수'다.
    """
    today = datetime.now(KST).date()
    start = today - timedelta(days=days - 1)
    since = datetime.combine(start, datetime.min.time(), tzinfo=KST)

    signups = _daily_counts(db, User.created_at, since)
    runs = _daily_counts(db, Run.started_at, since)
    completions = _daily_counts(db, Stamp.acquired_at, since)
    favorites = _daily_counts(db, Favorite.created_at, since)
    coupons = _daily_counts(db, UserCoupon.issued_at, since)
    # course_views.view_date는 이미 KST 날짜라 변환 없이 묶는다.
    view_rows = db.execute(
        select(CourseView.view_date, func.count())
        .where(CourseView.view_date >= start)
        .group_by(CourseView.view_date)
    ).all()
    views = {d: n for d, n in view_rows}

    return [
        {
            "date": d,
            "signups": signups.get(d, 0),
            "views": views.get(d, 0),
            "runs": runs.get(d, 0),
            "completions": completions.get(d, 0),
            "favorites": favorites.get(d, 0),
            "coupons_issued": coupons.get(d, 0),
        }
        for d in (start + timedelta(days=i) for i in range(days))
    ]


@router.get("/stats/stamps", response_model=list[StampDistributionOut])
def stats_stamp_distribution(db: Session = Depends(get_db)):
    """스탬프 보유 개수별 회원 수(0개 포함, 개수 오름차순). (관리자 전용)

    스탬프는 탈퇴자 것도 남으므로 1개 이상 구간은 탈퇴자를 포함한다. 0개는
    '현재 가입 회원 - 1개 이상 보유자'로 근사한다(음수면 0).
    """
    per_user = (
        select(Stamp.user_id, func.count(Stamp.id).label("n"))
        .group_by(Stamp.user_id)
        .subquery()
    )
    rows = db.execute(
        select(per_user.c.n, func.count()).group_by(per_user.c.n).order_by(per_user.c.n)
    ).all()
    registered = db.scalar(
        select(func.count()).select_from(User).where(User.deleted_at.is_(None))
    )
    holders = sum(users for _, users in rows)

    return [{"stamps": 0, "users": max(registered - holders, 0)}] + [
        {"stamps": n, "users": users} for n, users in rows
    ]
