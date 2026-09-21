"""앱 행동 로그 수신 — POST /user-logs (배치). 앱의 UserLogApi.writeUserLog가 부른다.

앱은 이벤트를 몇 초 모았다가 배열로 보낸다. 로그인 전 이벤트도 받아야 하므로 토큰은
선택(optional_user_id)이고, 있으면 user_id를 채운다. 응답은 204 — 앱은 결과를 기다리지
않고(fire-and-forget) 실패해도 조용히 버린다.

검증은 두 가지다. log_name은 허용 목록 안이어야 하고(오타·임의 문자열 차단), detail은
직렬화 크기 상한을 넘으면 안 된다(경로·이미지 같은 큰 값 차단). 하나라도 어긋나면 묶음
전체를 422로 거절한다 — 부분 성공은 앱이 재시도 판단을 못 하게 만든다.
"""

import json

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import insert
from sqlalchemy.orm import Session

from app import user_log
from app.db import get_db
from app.deps import optional_user_id
from app.models import UserLog
from app.schemas import UserLogBatchIn

router = APIRouter(tags=["user-logs"])


def validate_batch(payload: UserLogBatchIn) -> list[dict]:
    """묶음을 검증해 insert용 row dict 목록으로 바꾼다. 어긋나면 HTTPException(422)."""
    rows = []
    for index, event in enumerate(payload.logs):
        if event.log_name not in user_log.LOG_NAMES:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"logs[{index}]: 알 수 없는 log_name '{event.log_name}'",
            )
        size = len(json.dumps(event.detail, ensure_ascii=False).encode())
        if size > user_log.DETAIL_MAX_BYTES:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"logs[{index}]: detail이 너무 커요 ({size}B > {user_log.DETAIL_MAX_BYTES}B)",
            )
        rows.append(
            {
                "log_name": event.log_name,
                "detail": event.detail,
                "session_id": event.session_id,
                "platform": event.platform,
                "app_version": event.app_version,
            }
        )
    return rows


@router.post("/user-logs", status_code=status.HTTP_204_NO_CONTENT)
def write_user_log(
    payload: UserLogBatchIn,
    db: Session = Depends(get_db),
    user_id: str | None = Depends(optional_user_id),
):
    rows = validate_batch(payload)
    for row in rows:
        row["user_id"] = user_id

    # 묶음을 executemany 한 번으로 넣는다(행마다 왕복하지 않게).
    db.execute(insert(UserLog), rows)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
