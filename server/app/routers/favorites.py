import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id, current_user_is_admin
from app.models import Course, Favorite
from app.routers.courses import (
    _completed_counts,
    _my_completed_course_ids,
    _to_summary,
    visible_courses,
)
from app.schemas import CourseListItem

router = APIRouter(tags=["favorites"])


@router.get("/favorites", response_model=list[CourseListItem])
def list_favorites(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
    is_admin: bool = Depends(current_user_is_admin),
):
    """내가 찜한 코스 목록. 코스 목록(GET /courses)과 같은 형태로 내려준다 —
    클라이언트가 같은 CourseCard로 그대로 그린다."""
    # 찜한 순서(최근이 위)를 유지한다.
    course_ids = list(
        db.execute(
            select(Favorite.course_id)
            .where(Favorite.user_id == user_id)
            .order_by(Favorite.created_at.desc())
        ).scalars()
    )
    if not course_ids:
        return []

    # 찜한 뒤 숨겨진 코스는 목록에서 빠진다 — GET /courses와 같은 기준.
    courses = list(
        db.execute(
            visible_courses(select(Course).where(Course.id.in_(course_ids)), is_admin)
        ).scalars()
    )
    # IN 절은 순서를 보장하지 않으므로 찜 순서로 다시 세운다.
    rank = {cid: i for i, cid in enumerate(course_ids)}
    courses.sort(key=lambda c: rank[c.id])

    ids = [c.id for c in courses]
    counts = _completed_counts(db, ids)
    mine = _my_completed_course_ids(db, user_id, ids)

    return [
        _to_summary(course, counts.get(course.id, 0), course.id in mine)
        for course in courses
    ]


@router.post("/favorites/{course_id}", status_code=status.HTTP_204_NO_CONTENT)
def add_favorite(
    course_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """코스를 찜한다. 이미 찜했으면 아무 일도 없다(멱등)."""
    if db.get(Course, course_id) is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    exists = db.execute(
        select(Favorite).where(
            Favorite.user_id == user_id, Favorite.course_id == course_id
        )
    ).scalar_one_or_none()
    if exists is None:
        db.add(Favorite(user_id=user_id, course_id=course_id))
        db.commit()


@router.delete("/favorites/{course_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_favorite(
    course_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """찜을 해제한다. 찜하지 않은 코스여도 성공으로 친다(멱등)."""
    favorite = db.execute(
        select(Favorite).where(
            Favorite.user_id == user_id, Favorite.course_id == course_id
        )
    ).scalar_one_or_none()
    if favorite is not None:
        db.delete(favorite)
        db.commit()
