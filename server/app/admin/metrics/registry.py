"""지표 등록부. 이름 → (표시명, 세는 함수, 지원 group_by).

두 갈래로 채운다.
- 자동: user_log.LOG_NAMES의 모든 이름. 행 수를 세고 none/day를 지원하며,
  detail에 course_id를 넣는 로그(COURSE_LOGS)는 course도 지원한다. 앱에 로그를
  새로 심으면 서버 수정 없이 여기 나타난다.
- 명시: 로그 행 수가 아닌 것들 — 고유 조회, 가입/완주/찜 같은 상태 테이블, 미완주처럼
  둘을 조합한 파생 지표.
"""

from dataclasses import dataclass

from app import user_log
from app.admin.metrics import sources
from app.models import Favorite, Run, Stamp, User, UserCoupon, Verification

ALL_GROUP_BYS = ("none", "day", "course")
NO_COURSE = ("none", "day")


@dataclass(frozen=True)
class Metric:
    name: str
    label: str
    count: sources.Counter
    group_bys: tuple[str, ...]
    # 운영 웹 일별 추이의 탭. GROUPS 중 하나여야 한다(테스트가 강제).
    group: str = "기타"


# detail에 course_id를 담는 로그 — 코스별 집계가 의미 있는 것들.
COURSE_LOGS: frozenset[str] = frozenset(
    {
        "course_detail_open",
        "course_preview_open",
        "home_course_click",
        "favorite_add",
        "favorite_remove",
        "navigate_click",
        "run_start",
        "run_pause",
        "run_resume",
        "run_finish",
        "run_abandon",
        "run_upload_failed",
        "run_detail_open",
        "stamp_detail_open",
    }
)

# 운영 웹 탭. 순서는 프론트가 정하고 여기서는 허용값만 관리한다.
GROUPS = ("계정", "러닝", "코스", "스탬프·쿠폰", "기타")

# 로그 이름 접두사 → 탭. 접두사에 안 걸리면 LOG_GROUPS의 개별 지정, 그것도 없으면 '기타'.
GROUP_BY_PREFIX = (
    ("run_", "러닝"),
    ("course_", "코스"),
    ("favorite_", "코스"),
    ("coupon_", "스탬프·쿠폰"),
    ("stamp_", "스탬프·쿠폰"),
    ("login", "계정"),
)
LOG_GROUPS = {
    "home_course_click": "코스",
    "navigate_click": "코스",
    "logout": "계정",
    "withdraw": "계정",
    # 홈 배너·알림·외부 링크·앱 실행은 특정 도메인이 아니라 기타.
}


def _group_of(name: str) -> str:
    if name in LOG_GROUPS:
        return LOG_GROUPS[name]
    for prefix, group in GROUP_BY_PREFIX:
        if name.startswith(prefix):
            return group
    return "기타"


# 운영 웹에 보여줄 한글 표시명. 없으면 이름을 그대로 쓴다.
LOG_LABELS = {
    "app_open": "앱 실행",
    "home_course_click": "홈 코스 클릭",
    "banner_click": "배너 클릭",
    "notification_open": "알림 열기",
    "course_detail_open": "코스 상세 조회(클릭)",
    "course_preview_open": "코스 미리보기",
    "course_search": "코스 검색",
    "course_list_sort": "코스 정렬",
    "favorite_add": "즐겨찾기 추가",
    "favorite_remove": "즐겨찾기 해제",
    "navigate_click": "길찾기 클릭",
    "run_start": "러닝 시작",
    "run_pause": "러닝 일시정지",
    "run_resume": "러닝 재개",
    "run_finish": "러닝 종료",
    "run_abandon": "러닝 이탈",
    "run_upload_failed": "러닝 업로드 실패",
    "run_detail_open": "러닝 기록 열기",
    "stamp_detail_open": "스탬프 상세",
    "coupon_view": "쿠폰 보기",
    "coupon_use_click": "쿠폰 사용 클릭",
    "external_link_open": "외부 링크",
    "login": "로그인",
    "login_failed": "로그인 실패",
    "logout": "로그아웃",
    "withdraw": "탈퇴",
}


def _log_metrics() -> list[Metric]:
    return [
        Metric(
            name=name,
            label=LOG_LABELS.get(name, name),
            count=sources.log_count(name),
            group_bys=ALL_GROUP_BYS if name in COURSE_LOGS else NO_COURSE,
            group=_group_of(name),
        )
        for name in sorted(user_log.LOG_NAMES)
    ]


_course_runs = sources.table_count(
    Run.started_at, Run.course_id.is_not(None), course_column=Run.course_id
)
_matched_runs = sources.table_count(
    Verification.completed_at,
    Verification.status == "matched",
    course_column=Verification.course_id,
)

_EXPLICIT: list[Metric] = [
    Metric(
        "course_detail_open_unique",
        "코스 상세 조회(고유)",
        sources.log_unique_person_day(user_log.COURSE_DETAIL_OPEN),
        ALL_GROUP_BYS,
        group="코스",
    ),
    # 회원. registered_users는 '현재' 스냅샷이라 기간과 무관하다.
    Metric("signups", "가입", sources.table_count(User.created_at), NO_COURSE, group="계정"),
    Metric(
        "registered_users",
        "가입 회원(현재)",
        sources.snapshot_count(User, User.deleted_at.is_(None)),
        ("none",),
        group="계정",
    ),
    Metric(
        "active_users",
        "실이용자(러닝 1회 이상)",
        sources.distinct_users(Run.user_id, Run.started_at),
        NO_COURSE,
        group="계정",
    ),
    # 러닝. runs는 자유 러닝 포함, course_runs는 코스 따라가기만.
    Metric("runs", "러닝(전체)", sources.table_count(Run.started_at), NO_COURSE, group="러닝"),
    Metric("course_runs", "코스 러닝", _course_runs, ALL_GROUP_BYS, group="러닝"),
    Metric("matched_runs", "검증 통과", _matched_runs, ALL_GROUP_BYS, group="러닝"),
    Metric(
        "incomplete_runs",
        "미완주 러닝",
        sources.difference(_course_runs, _matched_runs),
        ALL_GROUP_BYS,
        group="러닝",
    ),
    Metric(
        "runners",
        "코스 이용자(고유)",
        sources.distinct_users(Run.user_id, Run.started_at, course_column=Run.course_id),
        ALL_GROUP_BYS,
        group="러닝",
    ),
    Metric(
        "completions",
        "완주(스탬프)",
        sources.table_count(Stamp.acquired_at, course_column=Stamp.course_id),
        ALL_GROUP_BYS,
        # 완주는 러닝의 결과라 러닝 탭에 둔다(스탬프 탭이 아니라).
        group="러닝",
    ),
    Metric(
        "favorites",
        "즐겨찾기(현재)",
        sources.table_count(Favorite.created_at, course_column=Favorite.course_id),
        ALL_GROUP_BYS,
        group="코스",
    ),
    Metric(
        "coupons_issued",
        "쿠폰 발급",
        sources.table_count(UserCoupon.issued_at),
        NO_COURSE,
        group="스탬프·쿠폰",
    ),
    Metric(
        "coupons_used",
        "쿠폰 사용",
        sources.table_count(UserCoupon.used_at, UserCoupon.used_at.is_not(None)),
        NO_COURSE,
        group="스탬프·쿠폰",
    ),
]

METRICS: dict[str, Metric] = {m.name: m for m in [*_log_metrics(), *_EXPLICIT]}
