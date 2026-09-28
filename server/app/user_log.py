"""user_log 공용 — 허용 로그 이름과 기록 헬퍼.

앱(POST /user-logs)과 서버 내부(코스 상세 조회 기록)가 같은 테이블에 쓰므로 로그 이름
목록을 여기서 한 번만 관리한다. 목록에 없는 이름은 거절해 오타·임의 문자열이
쌓이는 것을 막는다. 새 로그를 추가할 때는 이 목록에 먼저 넣는다.
"""

from sqlalchemy import insert
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.models import UserLog

# detail(JSONB) 한 건의 직렬화 상한(바이트). 경로·이미지 같은 큰 값을 막는다.
DETAIL_MAX_BYTES = 2048

# 서버가 직접 기록하는 로그.
COURSE_DETAIL_OPEN = "course_detail_open"

LOG_NAMES: frozenset[str] = frozenset(
    {
        COURSE_DETAIL_OPEN,
        # 홈
        "home_course_click",
        "banner_click",
        "notification_open",
        # 코스 탐색
        "course_preview_open",
        "course_search",
        "course_list_sort",
        "favorite_add",
        "favorite_remove",
        "navigate_click",
        # 러닝
        "run_start",
        "run_pause",
        "run_resume",
        "run_finish",
        "run_abandon",
        "run_upload_failed",
        "run_detail_open",
        "run_share",
        "run_share_failed",
        # 스탬프·쿠폰
        "stamp_detail_open",
        "coupon_view",
        "coupon_use_click",
        # 커뮤니티
        "external_link_open",
        # 계정
        "login",
        "login_failed",
        "logout",
        "withdraw",
        # 세션
        "app_open",
    }
)

PLATFORMS: frozenset[str] = frozenset({"android", "ios"})


def record_best_effort(
    db: Session,
    *,
    log_name: str,
    user_id: str | None,
    detail: dict,
    session_id: str | None = None,
    platform: str | None = None,
    app_version: str | None = None,
) -> None:
    """서버 내부 기록용(best-effort). 실패해도 롤백만 하고 호출한 요청은 성공시킨다.

    분석용 쓰기가 핵심 읽기(코스 상세 등)를 깨면 안 되기 때문이다. 세션·플랫폼·앱
    버전은 요청 헤더(deps.client_context)에서 온 값이고, 없으면 null로 남는다.
    """
    stmt = insert(UserLog).values(
        log_name=log_name,
        user_id=user_id,
        detail=detail,
        session_id=session_id,
        platform=platform,
        app_version=app_version,
    )
    try:
        db.execute(stmt)
        db.commit()
    except SQLAlchemyError:
        db.rollback()
