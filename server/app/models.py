import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

# 경로(path)는 JSONB에 [{"lat": .., "lng": .., ...}, ...] 형태로 그대로 저장한다.
#
# PostGIS geography(LineString) 대신 JSONB를 쓴 이유: 현재 클라이언트가 쓰는 API에는
# 공간 질의(예: 내 주변 코스 검색)가 없고, 경로는 "그려주기 / 순서대로 비교하기"에만
# 쓰인다. 둘 다 JSONB로 충분하다. 주변 검색 같은 공간 질의가 실제로 필요해지는 시점에
# geography 컬럼을 추가하는 편이 낫다.


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(String(2000), default=None)
    region: Mapped[str | None] = mapped_column(String(100), default=None, index=True)

    # 'easy' | 'normal' | 'hard' — 클라이언트 CourseDifficulty.name과 값이 같아야 한다.
    difficulty: Mapped[str] = mapped_column(String(20), default="normal")

    distance_meters: Mapped[float] = mapped_column(Float)
    estimated_duration_sec: Mapped[int | None] = mapped_column(Integer, default=None)
    elevation_gain_meters: Mapped[float | None] = mapped_column(Float, default=None)
    thumbnail_url: Mapped[str | None] = mapped_column(String(500), default=None)

    path: Mapped[list] = mapped_column(JSONB, default=list)

    created_by: Mapped[str | None] = mapped_column(String(100), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    stamps: Mapped[list["Stamp"]] = relationship(back_populates="course")


class Run(Base):
    __tablename__ = "runs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(String(100), index=True)

    # 코스를 따라 달린 경우에만 채워진다. 자유 러닝이면 None.
    course_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("courses.id"), default=None, index=True
    )

    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    distance_meters: Mapped[float] = mapped_column(Float)
    duration_sec: Mapped[int] = mapped_column(Integer)

    path: Mapped[list] = mapped_column(JSONB, default=list)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    course: Mapped[Course | None] = relationship()


class Verification(Base):
    """러닝 경로가 코스와 일치하는지에 대한 검증 결과."""

    __tablename__ = "verifications"
    __table_args__ = (UniqueConstraint("run_id", "course_id", name="uq_verification_run_course"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    run_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("runs.id"), index=True
    )
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("courses.id"), index=True
    )

    # 'pending' | 'inProgress' | 'matched' | 'mismatched' | 'failed'
    # 클라이언트 VerificationStatus.name과 값이 같아야 한다(특히 camelCase인 inProgress).
    status: Mapped[str] = mapped_column(String(20), default="pending")

    match_rate: Mapped[float | None] = mapped_column(Float, default=None)
    detail: Mapped[str | None] = mapped_column(String(500), default=None)

    requested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    run: Mapped[Run] = relationship()
    course: Mapped[Course] = relationship()


class Stamp(Base):
    """코스 완주 스탬프. 검증이 matched일 때만 발급된다."""

    __tablename__ = "stamps"
    __table_args__ = (UniqueConstraint("user_id", "course_id", name="uq_stamp_user_course"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(String(100), index=True)
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("courses.id"), index=True
    )
    run_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("runs.id"), default=None
    )

    image_url: Mapped[str | None] = mapped_column(String(500), default=None)
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    course: Mapped[Course] = relationship(back_populates="stamps")
