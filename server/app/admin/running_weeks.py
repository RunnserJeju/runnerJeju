"""운영자 전용 러닝위크 API — 회차 등록/수정, 배너 이미지, 빙고 배치, 참가자 조회, 완주 수동 인정.

앱 조회·참가 신청은 app.routers.running_weeks에 있다. 배너 이미지는 공지처럼 텍스트
폼(JSON)과 파일(multipart)을 섞지 않으려고 PUT/DELETE /running-weeks/{id}/image로 뗐다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy import String, cast, func, or_, select
from sqlalchemy.orm import Session

from app import bingo, running_week, stamp_rules, storage
from app.admin import audit
from app.admin.auth import require_admin_session
from app.db import get_db
from app.models import (
    AdminUser,
    Course,
    Coupon,
    RunningWeek,
    RunningWeekParticipation,
    Stamp,
    StampDefinition,
    User,
    UserCoupon,
)
from app.schemas import (
    AdminBingoOut,
    AdminCompletionRequest,
    AdminCompletionResult,
    AdminParticipantSearchOut,
    AdminParticipationOut,
    AdminRunningWeekOut,
    BingoUpdate,
    RunningWeekCreate,
    RunningWeekUpdate,
)

router = APIRouter(tags=["running-weeks"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


def _load_or_404(db: Session, week_id: uuid.UUID) -> RunningWeek:
    week = db.get(RunningWeek, week_id)
    if week is None:
        raise HTTPException(status_code=404, detail="러닝위크를 찾을 수 없어요.")
    return week


def _participant_counts(db: Session, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    rows = db.execute(
        select(RunningWeekParticipation.running_week_id, func.count())
        .where(RunningWeekParticipation.running_week_id.in_(ids))
        .group_by(RunningWeekParticipation.running_week_id)
    ).all()
    return {week_id: count for week_id, count in rows}


def _to_out(db: Session, week: RunningWeek) -> AdminRunningWeekOut:
    out = AdminRunningWeekOut.model_validate(week)
    out.participant_count = _participant_counts(db, [week.id]).get(week.id, 0)
    return out


def _check_round_free(db: Session, round_: int, week_id: uuid.UUID | None = None) -> None:
    query = select(RunningWeek.id).where(RunningWeek.round == round_)
    if week_id is not None:
        query = query.where(RunningWeek.id != week_id)
    if db.execute(query).first() is not None:
        raise HTTPException(status_code=409, detail=f"{round_}회차는 이미 있어요.")


def _apply(week: RunningWeek, payload: RunningWeekCreate) -> None:
    if payload.round is not None:
        week.round = payload.round
    week.title = payload.title
    week.description = payload.description
    week.starts_at = payload.starts_at
    week.ends_at = payload.ends_at
    week.is_active = payload.is_active
    week.visibility = payload.visibility


@router.get("/running-weeks", response_model=list[AdminRunningWeekOut])
def list_running_weeks(db: Session = Depends(get_db)):
    """전체 회차(예약·종료·숨김 포함), 최신 등록순. (관리자 전용 — 라우터 레벨에서 강제)"""
    weeks = list(
        db.execute(select(RunningWeek).order_by(RunningWeek.created_at.desc())).scalars()
    )
    counts = _participant_counts(db, [w.id for w in weeks])
    result = []
    for week in weeks:
        out = AdminRunningWeekOut.model_validate(week)
        out.participant_count = counts.get(week.id, 0)
        result.append(out)
    return result


@router.post("/running-weeks", response_model=AdminRunningWeekOut, status_code=201)
def create_running_week(payload: RunningWeekCreate, db: Session = Depends(get_db)):
    if payload.round is not None:
        _check_round_free(db, payload.round)
    week = RunningWeek(bingo_stamp_ids=[], round=running_week.next_round(db))
    _apply(week, payload)
    db.add(week)
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.patch("/running-weeks/{week_id}", response_model=AdminRunningWeekOut)
def update_running_week(
    week_id: uuid.UUID, payload: RunningWeekUpdate, db: Session = Depends(get_db)
):
    week = _load_or_404(db, week_id)
    if payload.round is not None:
        _check_round_free(db, payload.round, week.id)
    _apply(week, payload)
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.put("/running-weeks/{week_id}/bingo", response_model=AdminRunningWeekOut)
def set_bingo(week_id: uuid.UUID, payload: BingoUpdate, db: Session = Depends(get_db)):
    """빙고 배치를 통째로 바꾼다. 25개 모두 실제 스탬프 종류여야 한다.

    배열 안 id에는 외래키가 없어서 여기서 확인한다. 숨긴 스탬프도 놓을 수는 있지만
    앱에는 빈 칸으로 보인다. 칸에는 이 회차 전용 코스 스탬프만 놓는다.
    """
    week = _load_or_404(db, week_id)
    allowed = {d.id for d in stamp_rules.running_week_course_definitions(db, week.id)}
    wrong = [str(i) for i in payload.stamp_ids if i not in allowed]
    if wrong:
        raise HTTPException(
            status_code=422,
            detail=f"이 회차 러닝위크 스탬프가 아니에요: {', '.join(wrong)}",
        )

    week.bingo_stamp_ids = [str(i) for i in payload.stamp_ids]
    db.commit()
    db.refresh(week)
    return _to_out(db, week)


@router.get(
    "/running-weeks/{week_id}/participations",
    response_model=list[AdminParticipationOut],
)
def list_participations(week_id: uuid.UUID, db: Session = Depends(get_db)):
    """참가자 목록(신청순). 앱 계정의 닉네임·이메일을 같이 준다.

    participations.user_id는 users.id의 FK가 아니라 토큰 sub 문자열이라 캐스트해서 outer join한다
    (탈퇴해 행이 없으면 닉네임·이메일은 None).
    """
    _load_or_404(db, week_id)
    rows = db.execute(
        select(RunningWeekParticipation, User.nickname, User.email)
        .outerjoin(User, cast(User.id, String) == RunningWeekParticipation.user_id)
        .where(RunningWeekParticipation.running_week_id == week_id)
        .order_by(RunningWeekParticipation.created_at)
    ).all()
    return [
        {
            **{c.name: getattr(p, c.name) for c in RunningWeekParticipation.__table__.columns},
            "nickname": nickname,
            "email": email,
        }
        for p, nickname, email in rows
    ]


@router.put("/running-weeks/{week_id}/image", response_model=AdminRunningWeekOut)
def set_running_week_image(
    week_id: uuid.UUID,
    file: UploadFile = File(..., description="커뮤니티 배너 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """커뮤니티 상단 배너를 올린다(교체 포함). 옛 파일은 새로 올린 뒤 지운다(공지와 같다)."""
    week = _load_or_404(db, week_id)

    extension = _ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")

    content = file.file.read(MAX_IMAGE_BYTES + 1)
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_IMAGE_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")

    try:
        new_url = storage.upload_image(
            content,
            content_type=file.content_type,
            extension=extension,
            bucket=storage.SUPABASE_STORAGE_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    old_url = week.image_url
    week.image_url = new_url
    db.commit()
    db.refresh(week)

    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return _to_out(db, week)


@router.delete("/running-weeks/{week_id}/image", response_model=AdminRunningWeekOut)
def delete_running_week_image(week_id: uuid.UUID, db: Session = Depends(get_db)):
    week = _load_or_404(db, week_id)
    image_url = week.image_url
    if image_url:
        week.image_url = None
        db.commit()
        db.refresh(week)
        storage.delete_image(image_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return _to_out(db, week)


# --- 코스 완주 수동 처리 ---------------------------------------------------
# 앱 오류로 완주 인증을 못 받은 참가자를 운영자가 구제하는 길. 스탬프 한 개만 넣는
# /stamps/{id}/issue와 달리 실제 인증 통과와 같은 함수를 불러 코스 스탬프·러닝위크 스탬프·
# 완주 쿠폰·빙고 보상이 한 번에 처리된다.


@router.get(
    "/running-weeks/{week_id}/participants/search",
    response_model=list[AdminParticipantSearchOut],
)
def search_participants(
    week_id: uuid.UUID,
    q: str = Query(min_length=1, max_length=100),
    db: Session = Depends(get_db),
):
    """닉네임·신청 이름·이메일 부분일치로 이 회차 참가자를 찾는다(최대 20명)."""
    _load_or_404(db, week_id)
    like = f"%{q.strip()}%"
    rows = db.execute(
        select(RunningWeekParticipation, User.nickname, User.email)
        .outerjoin(User, cast(User.id, String) == RunningWeekParticipation.user_id)
        .where(
            RunningWeekParticipation.running_week_id == week_id,
            or_(
                RunningWeekParticipation.name.ilike(like),
                User.nickname.ilike(like),
                User.email.ilike(like),
            ),
        )
        .order_by(RunningWeekParticipation.created_at)
        .limit(20)
    ).all()
    return [
        {"user_id": p.user_id, "nickname": nickname, "email": email, "name": p.name}
        for p, nickname, email in rows
    ]


def _bingo_out(db: Session, week: RunningWeek, user_id: str) -> dict:
    board = bingo.board(db, week, user_id)
    if board is None:
        raise HTTPException(status_code=400, detail="이 회차는 빙고판 배치가 아직 없어요.")
    return {**board, "participated": running_week.participated(db, week.id, user_id)}


@router.get("/running-weeks/{week_id}/bingo", response_model=AdminBingoOut)
def get_participant_bingo(
    week_id: uuid.UUID, user_id: str = Query(min_length=1), db: Session = Depends(get_db)
):
    """한 사람의 빙고판 현황. 앱이 보는 것과 같은 계산."""
    week = _load_or_404(db, week_id)
    return _bingo_out(db, week, user_id)


@router.post(
    "/running-weeks/{week_id}/completions",
    response_model=AdminCompletionResult,
    status_code=201,
)
def complete_course(
    week_id: uuid.UUID,
    payload: AdminCompletionRequest,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin_session),
):
    """참가자의 코스 완주를 운영자가 인정한다. 실제 완주 인증 통과와 같은 흐름 —
    코스 스탬프 → 러닝위크 스탬프 → 완주 쿠폰 추첨 → 빙고 스탬프·줄 리워드 추첨.
    이미 받은 것은 각 규칙이 멱등이라 다시 주지 않는다. run_id는 None(러닝 없이 인정)."""
    week = _load_or_404(db, week_id)
    user_id = payload.user_id
    if db.execute(select(User.id).where(cast(User.id, String) == user_id)).first() is None:
        raise HTTPException(status_code=404, detail="회원을 찾을 수 없어요.")
    if not running_week.participated(db, week.id, user_id):
        raise HTTPException(status_code=400, detail="이 회차 참가자가 아니에요.")
    course = db.get(Course, payload.course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    def stamp_ids() -> set[uuid.UUID]:
        return set(db.execute(select(Stamp.id).where(Stamp.user_id == user_id)).scalars())

    def coupon_ids() -> set[uuid.UUID]:
        return set(
            db.execute(select(UserCoupon.id).where(UserCoupon.user_id == user_id)).scalars()
        )

    stamps_before, coupons_before = stamp_ids(), coupon_ids()
    stamp_rules.on_course_completed(db, user_id, payload.course_id, None)
    running_week.on_course_completed(db, user_id, payload.course_id, None, week=week)
    audit.record(
        db, admin, audit.COURSE_COMPLETE,
        target_type="course", target_id=course.id, user_id=user_id,
        detail={"course_name": course.name, "running_week_id": str(week.id)},
    )
    db.commit()

    new_stamps = stamp_ids() - stamps_before
    new_coupons = coupon_ids() - coupons_before
    granted_stamps = list(
        db.execute(
            select(StampDefinition.name)
            .join(Stamp, Stamp.stamp_definition_id == StampDefinition.id)
            .where(Stamp.id.in_(new_stamps))
            .order_by(Stamp.acquired_at)
        ).scalars()
    ) if new_stamps else []
    granted_coupons = list(
        db.execute(
            select(Coupon.name)
            .join(UserCoupon, UserCoupon.coupon_id == Coupon.id)
            .where(UserCoupon.id.in_(new_coupons))
            .order_by(UserCoupon.issued_at)
        ).scalars()
    ) if new_coupons else []
    return {
        "granted_stamps": granted_stamps,
        "granted_coupons": granted_coupons,
        "bingo": _bingo_out(db, week, user_id),
    }
