import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

# 경로(path)는 JSONB에 [{"lat": .., "lng": .., ...}, ...] 형태로 그대로 저장한다.
#
# PostGIS geography(LineString) 대신 JSONB를 쓴 이유: 현재 클라이언트가 쓰는 API에는
# 공간 질의(예: 내 주변 코스 검색)가 없고, 경로는 "그려주기 / 순서대로 비교하기"에만
# 쓰인다. 둘 다 JSONB로 충분하다. 주변 검색 같은 공간 질의가 실제로 필요해지는 시점에
# geography 컬럼을 추가하는 편이 낫다.


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # 카카오/애플 둘 다 로그인 provider이므로 둘 중 하나만 있어도 되게 nullable이다.
    kakao_id: Mapped[str | None] = mapped_column(
        String(100), unique=True, index=True, default=None
    )
    apple_id: Mapped[str | None] = mapped_column(
        String(100), unique=True, index=True, default=None
    )
    google_id: Mapped[str | None] = mapped_column(
        String(100), unique=True, index=True, default=None
    )
    nickname: Mapped[str | None] = mapped_column(String(100), default=None)
    profile_image_url: Mapped[str | None] = mapped_column(String(500), default=None)
    # provider가 동의항목으로 내려줄 때만 채워진다. 로그인 식별자가 아니라
    # 참고용 정보라 unique 제약은 안 건다 (카카오/애플 두 provider가 같은
    # 사람이라도 별개 계정이라 같은 이메일을 가질 수 있다).
    email: Mapped[str | None] = mapped_column(String(255), default=None)

    # 'user' | 'admin' — 코스 등록(admin 전용) 권한 구분용.
    role: Mapped[str] = mapped_column(String(20), default="user")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class RefreshToken(Base):
    """발급된 refresh token 1개. 로그아웃 시 revoked_at을 채워 폐기한다."""

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), index=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Course(Base):
    """관리자가 코스 명단(courses/courses.yaml)을 기준으로 올리는 러닝 코스.

    컬럼은 명단 시트가 가진 항목과 1:1이다. 코스 수정이나 재업로드를 코드로
    다루지 않는다 — 고칠 일이 생기면 DB에서 직접 고치거나 다시 올린다.
    """

    __tablename__ = "courses"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    name: Mapped[str] = mapped_column(String(200))

    # 왕복 기준 km. GPX에서 계산한 실측 거리가 아니라 명단에 적힌 안내값이라
    # 정수로 충분하다. 러닝 진행률처럼 정확도가 필요한 계산은 이 값이 아니라
    # path에서 직접 거리를 재서 쓴다.
    distance_km: Mapped[int] = mapped_column(Integer)

    # 1=★, 2=★★, 3=★★★ — 클라이언트 CourseDifficulty.value와 값이 같아야 한다.
    difficulty: Mapped[int] = mapped_column(SmallInteger)

    # "해안도로,제주시,동쪽" 처럼 쉼표로 이어 붙인다. 태그로 코스를 걸러내는
    # 화면이 아직 없어서 별도 테이블이나 배열 타입까지 갈 이유가 없었다.
    tags: Mapped[str | None] = mapped_column(String(200), default=None)

    address: Mapped[str] = mapped_column(String(300))

    # 명단에 값이 없는 코스가 있어서 둘 다 nullable이다.
    parking_address: Mapped[str | None] = mapped_column(String(300), default=None)
    restroom_address: Mapped[str | None] = mapped_column(String(300), default=None)

    description: Mapped[str | None] = mapped_column(String(2000), default=None)

    path: Mapped[list] = mapped_column(JSONB, default=list)

    created_by: Mapped[str | None] = mapped_column(String(100), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
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


class Banner(Base):
    """홈 화면 상단 이미지 배너. 관리자가 앱에서 직접 올린다.

    image_url은 Supabase Storage의 public URL이다(app.storage 참고) — 이 테이블은
    이미지 파일 자체가 아니라 어디 있는지와 노출 여부/순서만 안다.
    """

    __tablename__ = "banners"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    image_url: Mapped[str] = mapped_column(String(500))

    # 낮을수록 먼저 보인다. 같은 값이면 created_at으로 tie-break(목록 쿼리 참고).
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_by: Mapped[str | None] = mapped_column(String(100), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Notice(Base):
    """홈 화면에 노출되는 공지사항. 관리자가 DB에 직접 등록한다."""

    __tablename__ = "notices"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
