"""지표를 세는 방법들. 각 함수는 (db, 기간, group_by) → [(key, count)]를 돌려준다.

key는 group_by에 따라 None(합계) / date(일별) / 코스 id(코스별)다. 코스명 조인과
빈 날짜 0 채우기는 router가 공통으로 처리하므로 여기서는 세기만 한다.

'하루'는 KST 기준이고, 기간 [start, end]는 날짜 단위 양끝 포함이다. 상한이 없으면
(end=None) 오늘까지, 하한이 없으면(start=None) 처음부터다.
"""

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import Date, String, cast, distinct, func, literal_column, select
from sqlalchemy.orm import Session

from app.models import User, UserLog
from app.routers.courses import KST

GroupBy = str  # "none" | "day" | "course"
Rows = list[tuple[object, int]]
Counter = Callable[[Session, date | None, date | None, GroupBy], Rows]


@dataclass(frozen=True)
class Period:
    """KST 날짜 구간을 timestamptz 비교용 경계로 바꾼다."""

    start: date | None
    end: date | None

    def clauses(self, column):
        conditions = []
        if self.start is not None:
            conditions.append(column >= datetime.combine(self.start, datetime.min.time(), KST))
        if self.end is not None:
            next_day = self.end + timedelta(days=1)
            conditions.append(column < datetime.combine(next_day, datetime.min.time(), KST))
        return conditions


def kst_date(column):
    """timestamptz → KST 날짜. 시간대는 리터럴이어야 SELECT/GROUP BY가 같은 식이 된다."""
    return cast(func.timezone(literal_column("'Asia/Seoul'"), column), Date)


def _grouped(stmt, key_expr, group_by: GroupBy):
    """count 문장에 group_by 차원을 씌운다. none이면 (None, count) 한 줄."""
    if group_by == "none":
        return stmt.add_columns(literal_column("NULL").label("key"))
    return stmt.add_columns(key_expr.label("key")).group_by(key_expr)


def _run(db: Session, stmt) -> Rows:
    return [(row.key, row.count) for row in db.execute(stmt).all()]


# --- user_log 기반 ---------------------------------------------------------

_LOG_COURSE_ID = UserLog.detail["course_id"].astext


def log_count(log_name: str) -> Counter:
    """user_log에서 log_name 행 수."""

    def count(db, start, end, group_by):
        key = kst_date(UserLog.created_at) if group_by == "day" else _LOG_COURSE_ID
        stmt = (
            select(func.count().label("count"))
            .select_from(UserLog)
            .where(UserLog.log_name == log_name, *Period(start, end).clauses(UserLog.created_at))
        )
        return _run(db, _grouped(stmt, key, group_by))

    return count


def log_unique_person_day(log_name: str) -> Counter:
    """user_log에서 (사람·코스·KST 날짜) 고유 조합 수 — 옛 course_views의 '고유 조회'."""

    def count(db, start, end, group_by):
        day = kst_date(UserLog.created_at)
        unique = (
            select(_LOG_COURSE_ID.label("course_id"), UserLog.user_id, day.label("day"))
            .where(UserLog.log_name == log_name, *Period(start, end).clauses(UserLog.created_at))
            .group_by(_LOG_COURSE_ID, UserLog.user_id, day)
            .subquery()
        )
        key = unique.c.day if group_by == "day" else unique.c.course_id
        stmt = select(func.count().label("count")).select_from(unique)
        return _run(db, _grouped(stmt, key, group_by))

    return count


# --- 상태 테이블 기반 -------------------------------------------------------


def table_count(ts_column, *filters, course_column=None) -> Counter:
    """상태 테이블 행 수. ts_column으로 기간을 거르고 일별로 묶는다."""

    def count(db, start, end, group_by):
        key = kst_date(ts_column) if group_by == "day" else course_column
        stmt = (
            select(func.count().label("count"))
            .select_from(ts_column.class_)
            .where(*filters, *Period(start, end).clauses(ts_column))
        )
        return _run(db, _grouped(stmt, key, group_by))

    return count


def distinct_users(user_column, ts_column, *filters, course_column=None) -> Counter:
    """고유 사용자 수(탈퇴자 제외). user_column은 토큰 sub 문자열이라 users.id를 캐스팅해 조인한다."""

    def count(db, start, end, group_by):
        key = kst_date(ts_column) if group_by == "day" else course_column
        stmt = (
            select(func.count(distinct(user_column)).label("count"))
            .select_from(ts_column.class_)
            .join(User, cast(User.id, String) == user_column)
            .where(User.deleted_at.is_(None), *filters, *Period(start, end).clauses(ts_column))
        )
        return _run(db, _grouped(stmt, key, group_by))

    return count


def difference(minuend: Counter, subtrahend: Counter) -> Counter:
    """두 지표의 차(키별, 음수는 0). 예: 미완주 러닝 = 코스 러닝 − 검증 통과."""

    def count(db, start, end, group_by):
        a = dict(minuend(db, start, end, group_by))
        b = dict(subtrahend(db, start, end, group_by))
        return [(key, max(a.get(key, 0) - b.get(key, 0), 0)) for key in a.keys() | b.keys()]

    return count


def snapshot_count(model, *filters) -> Counter:
    """시점 스냅샷(예: 현재 가입 회원 수). 기간을 무시하고 group_by=none만 지원한다."""

    def count(db, start, end, group_by):
        value = db.scalar(select(func.count()).select_from(model).where(*filters))
        return [(None, value or 0)]

    return count


def course_key(value) -> uuid.UUID | None:
    """코스별 키를 UUID로 통일한다 — 로그는 텍스트, 테이블은 UUID로 온다."""
    if value is None:
        return None
    try:
        return uuid.UUID(str(value))
    except ValueError:
        return None
