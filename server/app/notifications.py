"""알림 만들기와 푸시 발송.

알림은 notifications 행이 먼저다 — 행이 발송 명단이자 알림함이고, push_status가 pending인
행이 대기열이다. 발송기(dispatch)는 대기 행을 묶음으로 가져가 FCM에 보내고 결과를 적는다.
누가 dispatch를 부르든(운영툴 요청, 틱, push_now) 같은 행을 두 번 보내지 않는다.
"""

import time
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import bindparam, delete, insert, select, text, update
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Session

from app import fcm
from app.models import AdminUser, DeviceToken, Notification, NotificationSend

CHUNK = 500
MAX_ATTEMPTS = 3
# n번째 시도가 일시 오류로 끝났을 때 다음 시도까지.
_BACKOFF = (timedelta(minutes=1), timedelta(minutes=5))
# 발송기가 죽어 sending에 남은 행을 되돌리는 기준. 틱 한 번의 예산보다 넉넉히 길다.
_STALE_AFTER = timedelta(minutes=10)
# push_now가 요청 안에서 바로 보내는 최대 건수. 넘으면 틱이 가져간다.
_INLINE_LIMIT = 20
TICK_BUDGET_SEC = 45.0

AUDIENCE_KINDS = ("all", "authorized", "users")


def notify(
    db: Session,
    user_ids: list[str],
    *,
    type: str,
    title: str,
    body: str,
    link_url: str | None = None,
) -> list[uuid.UUID]:
    """시스템이 보내는 알림을 대기 행으로 넣는다. 커밋하지 않는다.

    본래 일(스탬프 지급 등)과 같은 트랜잭션에 넣어 같이 커밋되게 한다 — 지급만 되고 알림이
    빠지거나 그 반대가 없다. 푸시는 커밋 뒤 push_now로 바로 보낸다. 안 보냈거나 실패한 행은 다음 틱이 보낸다.
    """
    rows = [
        {
            "id": uuid.uuid4(),
            "user_id": user_id,
            "type": type,
            "title": title,
            "body": body,
            "link_url": link_url,
        }
        for user_id in dict.fromkeys(user_ids)
    ]
    if rows:
        db.execute(insert(Notification), rows)
    return [row["id"] for row in rows]


def push_now(db: Session, ids: list[uuid.UUID]) -> None:
    """notify한 행을 커밋 뒤에 바로 보낸다. 실패해도 예외를 올리지 않는다 — 틱이 다시 보낸다."""
    if not ids or len(ids) > _INLINE_LIMIT:
        return
    try:
        dispatch(db, ids=ids)
    except Exception:
        db.rollback()


def create_send(
    db: Session,
    admin: AdminUser,
    *,
    type: str,
    title: str,
    body: str,
    link_url: str | None,
    audience: dict,
    scheduled_at: datetime | None,
) -> NotificationSend:
    """운영자 발송 한 건. 즉시면 명단까지 만들고, 예약이면 틱이 시각에 맞춰 만든다. 커밋은 호출부."""
    send = NotificationSend(
        id=uuid.uuid4(),
        type=type,
        title=title,
        body=body,
        link_url=link_url,
        audience=audience,
        status="scheduled" if scheduled_at else "sending",
        scheduled_at=scheduled_at,
        admin_user_id=admin.id,
        admin_username=admin.username,
    )
    db.add(send)
    db.flush()
    if scheduled_at is None:
        send.target_count = _materialize(db, send)
    return send


_AUDIENCE_SQL = {
    "all": "",
    "authorized": (
        " AND EXISTS (SELECT 1 FROM device_tokens d"
        " WHERE d.user_id = u.id::text AND d.permission = 'authorized')"
    ),
    "users": " AND u.id = ANY(:user_ids)",
}


def _materialize(db: Session, send: NotificationSend) -> int:
    """대상 회원마다 대기 행을 만든다. 쿼리 한 번. 만든 수."""
    kind = send.audience["kind"]
    statement = text(
        "INSERT INTO notifications (id, send_id, user_id, type, title, body, link_url)"
        " SELECT gen_random_uuid(), :send_id, u.id::text, :type, :title, :body, :link_url"
        " FROM users u WHERE u.deleted_at IS NULL" + _AUDIENCE_SQL[kind]
    )
    params = {
        "send_id": send.id,
        "type": send.type,
        "title": send.title,
        "body": send.body,
        "link_url": send.link_url,
    }
    if kind == "users":
        statement = statement.bindparams(bindparam("user_ids", type_=ARRAY(UUID(as_uuid=True))))
        params["user_ids"] = [uuid.UUID(u) for u in send.audience["user_ids"]]
    return db.execute(statement, params).rowcount


def audience_count(db: Session, audience: dict) -> int:
    """발송 전 미리 보기용 대상 수."""
    kind = audience["kind"]
    statement = text(
        "SELECT count(*) FROM users u WHERE u.deleted_at IS NULL" + _AUDIENCE_SQL[kind]
    )
    params = {}
    if kind == "users":
        statement = statement.bindparams(bindparam("user_ids", type_=ARRAY(UUID(as_uuid=True))))
        params["user_ids"] = [uuid.UUID(u) for u in audience["user_ids"]]
    return db.execute(statement, params).scalar_one()


def dispatch(
    db: Session,
    *,
    send_id: uuid.UUID | None = None,
    ids: list[uuid.UUID] | None = None,
    limit: int = CHUNK,
) -> int:
    """보낼 차례인 대기 행을 limit개까지 보낸다. 가져간 수(0이면 더 없음).

    가져갈 때 sending으로 바꾸고 커밋하므로 다른 발송기와 겹치지 않는다. FCM을 기다리는 동안
    DB 연결은 쥐고 있지 않다.
    """
    scope, params = "", {"limit": limit}
    if send_id is not None:
        scope, params["send_id"] = " AND send_id = :send_id", send_id
    claim = text(
        "UPDATE notifications SET push_status = 'sending', attempts = attempts + 1,"
        " claimed_at = now()"
        " WHERE id IN (SELECT id FROM notifications"
        "  WHERE push_status = 'pending' AND next_attempt_at <= now()"
        + scope
        + (" AND id = ANY(:ids)" if ids is not None else "")
        + "  ORDER BY next_attempt_at LIMIT :limit FOR UPDATE SKIP LOCKED)"
        " RETURNING id, user_id, type, title, body, link_url, attempts"
    )
    if ids is not None:
        claim = claim.bindparams(bindparam("ids", type_=ARRAY(UUID(as_uuid=True))))
        params["ids"] = ids
    rows = db.execute(claim, params).all()
    if not rows:
        db.commit()
        return 0

    # 권한을 안 켠 기기에는 보내지 않는다 — FCM은 받아 주지만 화면에 뜨지 않아 성공으로 잘못 남는다.
    tokens: dict[str, list[str]] = {}
    for user_id, token, permission in db.execute(
        select(DeviceToken.user_id, DeviceToken.token, DeviceToken.permission).where(
            DeviceToken.user_id.in_({row.user_id for row in rows})
        )
    ):
        allowed = tokens.setdefault(user_id, [])
        if permission == "authorized":
            allowed.append(token)
    db.commit()

    messages: list[fcm.Message] = []
    owners: list[int] = []
    for index, row in enumerate(rows):
        data = {"notification_id": str(row.id), "type": row.type}
        if row.link_url:
            data["link"] = row.link_url
        for token in tokens.get(row.user_id, ()):
            messages.append(fcm.Message(token, row.title, row.body, data))
            owners.append(index)

    if fcm.enabled():
        results = fcm.send_all(messages)
    else:
        results = [(None, None)] * len(messages)

    now = datetime.now(timezone.utc)
    per_row: list[list[tuple[str | None, str | None]]] = [[] for _ in rows]
    dead: list[str] = []
    for message, index, result in zip(messages, owners, results):
        per_row[index].append(result)
        if result[0] == fcm.DEAD:
            dead.append(message.token)

    # 결과가 같은 행끼리 묶어 한 문장으로 쓴다(대부분 sent 하나로 끝난다).
    groups: dict[tuple, list[uuid.UUID]] = {}
    for index, row in enumerate(rows):
        if per_row[index]:
            outcome = _outcome(row.attempts, per_row[index], now)
        else:
            # 기기가 아예 없는지, 있는데 권한이 꺼졌는지.
            outcome = ("no_permission" if row.user_id in tokens else "no_device", None, None, now)
        groups.setdefault(outcome, []).append(row.id)
    for (status, error, pushed_at, next_attempt_at), group_ids in groups.items():
        db.execute(
            update(Notification)
            .where(Notification.id.in_(group_ids))
            .values(
                push_status=status,
                push_error=error,
                pushed_at=pushed_at,
                next_attempt_at=next_attempt_at,
            )
        )
    if dead:
        db.execute(delete(DeviceToken).where(DeviceToken.token.in_(dead)))
    db.commit()
    return len(rows)


def _outcome(
    attempts: int,
    results: list[tuple[str | None, str | None]],
    now: datetime,
) -> tuple[str, str | None, datetime | None, datetime]:
    """기기별 결과를 알림 한 건의 (상태, 사유, 보낸 시각, 다음 시도 시각)으로. 한 대라도 받았으면 sent."""
    kinds = [kind for kind, _ in results]
    if kinds[0] is None:
        # FCM이 꺼진 환경(로컬).
        return "skipped", None, None, now
    if fcm.OK in kinds:
        return "sent", None, now, now
    if fcm.RETRY in kinds and attempts < MAX_ATTEMPTS:
        reason = next(reason for kind, reason in results if kind == fcm.RETRY)
        return "pending", reason, None, now + _BACKOFF[attempts - 1]
    return "failed", next((reason for _, reason in results if reason), None), None, now


def tick(db: Session, budget_sec: float = TICK_BUDGET_SEC) -> dict:
    """Cloud Scheduler 주기(30분)마다 불린다. 예약 건을 열고, 대기 행을 예산 시간만큼 보내고, 끝난 발송을 마감한다."""
    deadline = time.monotonic() + budget_sec
    recovered = db.execute(
        text(
            "UPDATE notifications SET push_status = 'pending'"
            " WHERE push_status = 'sending' AND claimed_at < :before"
        ),
        {"before": datetime.now(timezone.utc) - _STALE_AFTER},
    ).rowcount
    db.commit()

    opened = _open_due_sends(db)

    sent = 0
    while time.monotonic() < deadline:
        count = dispatch(db)
        if count == 0:
            break
        sent += count

    finished = finish_sends(db)
    return {"recovered": recovered, "opened": opened, "dispatched": sent, "finished": finished}


def _open_due_sends(db: Session) -> int:
    """시각이 된 예약 건의 명단을 만든다. 상태 변경과 명단이 한 트랜잭션이라 중간에 죽어도 다시 열린다."""
    due = db.execute(
        select(NotificationSend)
        .where(
            NotificationSend.status == "scheduled",
            NotificationSend.scheduled_at <= datetime.now(timezone.utc),
        )
        .with_for_update(skip_locked=True)
    ).scalars().all()
    for send in due:
        send.status = "sending"
        send.target_count = _materialize(db, send)
    db.commit()
    return len(due)


def finish_sends(db: Session) -> int:
    """대기·발송 중인 행이 없는 발송을 done으로 바꾸고 건수를 한 번 세어 둔다."""
    finished = db.execute(
        text(
            "UPDATE notification_sends s SET status = 'done', finished_at = now(),"
            " sent_count = c.sent, failed_count = c.failed, no_device_count = c.no_device,"
            " no_permission_count = c.no_permission"
            " FROM (SELECT s2.id,"
            "   count(*) FILTER (WHERE n.push_status = 'sent') AS sent,"
            "   count(*) FILTER (WHERE n.push_status = 'failed') AS failed,"
            "   count(*) FILTER (WHERE n.push_status = 'no_device') AS no_device,"
            "   count(*) FILTER (WHERE n.push_status = 'no_permission') AS no_permission"
            "  FROM notification_sends s2 LEFT JOIN notifications n ON n.send_id = s2.id"
            "  WHERE s2.status = 'sending' GROUP BY s2.id"
            "  HAVING count(*) FILTER (WHERE n.push_status IN ('pending', 'sending')) = 0) c"
            " WHERE s.id = c.id"
        )
    ).rowcount
    db.commit()
    return finished
