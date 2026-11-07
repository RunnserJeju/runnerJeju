"""운영툴 행위 로그. 지급·회수·완주 인정처럼 데이터를 바꾸는 운영자 행위를 누가 언제 했는지 남긴다.

커밋은 부르는 쪽이 한다 — 행위와 같은 트랜잭션에 묶여, 행위가 실패하면 로그도 남지 않는다.
"""

import uuid

from sqlalchemy.orm import Session

from app.models import AdminAction, AdminUser

STAMP_ISSUE = "stamp_issue"
STAMP_REVOKE = "stamp_revoke"
COUPON_ISSUE = "coupon_issue"
COUPON_REVOKE = "coupon_revoke"
COURSE_COMPLETE = "course_complete"
REWARD_FULFILL = "reward_fulfill"


def record(
    db: Session,
    admin: AdminUser,
    action: str,
    *,
    target_type: str,
    target_id: uuid.UUID | str | None = None,
    user_id: str | None = None,
    detail: dict | None = None,
) -> None:
    db.add(
        AdminAction(
            admin_user_id=admin.id,
            admin_username=admin.username,
            action=action,
            target_type=target_type,
            target_id=None if target_id is None else str(target_id),
            user_id=user_id,
            detail=detail or {},
        )
    )
