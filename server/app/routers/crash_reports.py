"""앱 크래시 리포트 수신 — POST /crash-reports (multipart: meta JSON + 선택 덤프 gzip).

앱은 크래시 다음 실행 때 쌓아 둔 리포트를 한 건씩 올리고, 2xx를 받으면 기기에서 지운다.
그래서 같은 id가 다시 와도 204로 받아 준다. 저장소(Storage) 실패만 503으로 돌려 재시도하게
하고, 형식 오류(422)·너무 큰 덤프(413)는 앱이 버린다.

로그인 전 크래시도 받아야 해서 토큰은 선택이다(optional_user_id).
"""

import json
import zlib

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import crash_report, storage
from app.db import get_db
from app.deps import ClientContext, client_context, optional_user_id
from app.models import CrashReport
from app.schemas import CrashReportIn

router = APIRouter(tags=["crash-reports"])

META_MAX_BYTES = 128 * 1024
# 압축된 덤프 상한. ANR 전체 스레드 덤프도 압축하면 이 안에 든다.
DUMP_MAX_BYTES = 8 * 1024 * 1024
# 해석할 때 푸는 상한. 압축 폭탄이 메모리를 다 먹지 않게.
DUMP_MAX_INFLATED = 32 * 1024 * 1024
CONTEXT_MAX_BYTES = 8 * 1024


@router.post("/crash-reports", status_code=status.HTTP_204_NO_CONTENT)
def upload_crash_report(
    meta: str = Form(...),
    dump: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    user_id: str | None = Depends(optional_user_id),
    client: ClientContext = Depends(client_context),
):
    if len(meta.encode()) > META_MAX_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "meta가 너무 커요.")
    try:
        payload = CrashReportIn.model_validate_json(meta)
    except ValidationError as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error)[:500])

    if db.get(CrashReport, payload.id) is not None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    digest = crash_report.Digest()
    dump_path = None
    if dump is not None:
        data = dump.file.read(DUMP_MAX_BYTES + 1)
        if len(data) > DUMP_MAX_BYTES:
            raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "덤프가 너무 커요.")
        digest = crash_report.digest(payload.kind, _inflate(data))
        if storage.SUPABASE_URL:
            path = f"{payload.occurred_at:%Y/%m}/{payload.id}.gz"
            try:
                dump_path = storage.upload_private(
                    data, path=path, content_type="application/gzip", bucket=storage.SUPABASE_CRASH_BUCKET
                )
            except storage.StorageUploadError as error:
                raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(error))

    context = payload.context
    if len(json.dumps(context, ensure_ascii=False).encode()) > CONTEXT_MAX_BYTES:
        context = {"truncated": True}

    clip = crash_report.clip
    db.add(
        CrashReport(
            id=payload.id,
            user_id=user_id,
            session_id=client.session_id,
            platform=client.platform,
            app_version=client.app_version,
            device=clip(payload.device, 100),
            os_version=clip(payload.os_version, 100),
            kind=payload.kind,
            occurred_at=payload.occurred_at,
            summary=clip(digest.summary or payload.summary, crash_report.SUMMARY_MAX_CHARS),
            culprit=clip(digest.culprit, crash_report.CULPRIT_MAX_CHARS),
            stack=clip(digest.stack or payload.stack, crash_report.STACK_MAX_CHARS),
            dump_path=dump_path,
            context=context,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        # 같은 id가 동시에 두 번 왔다. 먼저 들어간 것으로 충분하다.
        db.rollback()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _inflate(data: bytes) -> bytes:
    """gzip을 풀되 상한까지만. gzip이 아니면 그대로(앱이 압축 없이 보낸 경우)."""
    if data[:2] != b"\x1f\x8b":
        return data
    try:
        return zlib.decompressobj(wbits=31).decompress(data, DUMP_MAX_INFLATED)
    except zlib.error:
        return b""
