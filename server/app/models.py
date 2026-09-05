import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
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
    # 운영 웹 회원 목록이 가입일 최신순 + id 2차키로 페이지네이션한다. 복합 인덱스로
    # 정렬을 인덱스 순서대로 읽어 전체 정렬을 피한다(PostgreSQL은 이 오름차순 인덱스를
    # 역방향으로 읽어 DESC 정렬도 처리한다). 나중에 keyset로 바꿔도 그대로 재사용한다.
    __table_args__ = (Index("ix_users_created_at_id", "created_at", "id"),)

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

    # 최근 로그인/토큰 리프레시 시각. 로그인(_issue_tokens)과 refresh에서 갱신한다.
    # 활성 이용자 통계·휴면 판정의 근거. 요청마다 갱신하지 않는다(무상태 인증 유지).
    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    # 채워지면 탈퇴(익명화)된 계정. PII가 스크럽된 husk이고 provider id도 null이라
    # 재로그인 시 새 계정이 생긴다. 회원 목록·활성 통계에서 이 값으로 거른다. 활동
    # (완주·찜)은 익명으로 남겨 역사적 집계에 유지한다.
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
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
    #
    # 아래 parkings/restrooms(JSONB)로 대체되는 중이다(단계적 교체 — 0009 마이그레이션
    # 주석 참고). 코드가 새 컬럼으로 완전히 넘어가면 옛 컬럼은 0010에서 지운다.
    parking_address: Mapped[str | None] = mapped_column(String(300), default=None)
    restroom_address: Mapped[str | None] = mapped_column(String(300), default=None)

    # 주차장/화장실을 코스당 여러 개 담는다. 각 원소는
    # {"name": str|null, "address": str, "lat": float, "lng": float}.
    # 좌표는 등록 시점에 주소를 변환(app/geocoding.py)해 넣는다. path와 같은 JSONB 전략.
    parkings: Mapped[list] = mapped_column(JSONB, default=list)
    restrooms: Mapped[list] = mapped_column(JSONB, default=list)

    description: Mapped[str | None] = mapped_column(String(2000), default=None)

    # 예상 소요시간(분). 명단에 없는 코스가 있어 nullable이다. 왕복 안내값인
    # distance_km처럼 실측이 아니라 안내용이라 분 단위 정수로 충분하다.
    estimated_time_min: Mapped[int | None] = mapped_column(Integer, default=None)

    # 대표 썸네일. 배너와 같은 Supabase Storage public URL(app.storage)이다. 값은
    # 전용 엔드포인트(PUT/DELETE /courses/{id}/thumbnail)가 업로드·교체·삭제하며
    # 채우고, 코스 등록/수정(GPX·메타데이터)은 이 컬럼을 건드리지 않는다.
    thumbnail_url: Mapped[str | None] = mapped_column(String(500), default=None)

    # 이 코스를 완주하면 주는 스탬프 도안(Supabase Storage public URL). 스탬프는
    # 코스에 1:1로 종속돼서 도안을 코스에 둔다. 발급된 스탬프(stamps)는 이 값을
    # 조회 시 참조하므로(라이브 참조), 운영자가 나중에 도안을 넣거나 바꿔도 이미
    # 완주한 사람에게까지 반영된다. 전용 엔드포인트(PUT/DELETE
    # /courses/{id}/stamp-image)가 채운다.
    stamp_image_url: Mapped[str | None] = mapped_column(String(500), default=None)

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

    # 스탬프 도안은 이 행이 아니라 코스(courses.stamp_image_url)에 있다 — 코스당
    # 하나이고 운영자가 설정하는 값이라, 완주 인스턴스마다 복제하지 않고 조회 시
    # course에서 라이브로 가져온다(stamps 라우터 _to_out 참고).
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    course: Mapped[Course] = relationship(back_populates="stamps")


class Favorite(Base):
    """사용자가 찜한 코스. (user_id, course_id)로 유일 — 같은 코스를 두 번 찜해도
    행은 하나다. 서버에 저장하므로 기기를 바꿔도 찜이 유지된다."""

    __tablename__ = "favorites"
    __table_args__ = (
        UniqueConstraint("user_id", "course_id", name="uq_favorite_user_course"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # Stamp/Run과 같게 토큰 sub(문자열)를 그대로 담는다.
    user_id: Mapped[str] = mapped_column(String(100), index=True)
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("courses.id"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    course: Mapped[Course] = relationship()


class Notice(Base):
    """홈 화면 공지사항. 이미지가 있으면 상단 배너 캐러셀에도 실린다.

    옛 banners 테이블(이미지만 있던 별도 리소스)은 0017에서 이쪽으로 합쳤다 —
    배너가 곧 공지 내용이라 두 번 등록할 이유가 없었다.
    """

    __tablename__ = "notices"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)

    # 배너 이미지(Supabase Storage public URL, app.storage). null이면 텍스트 공지만,
    # 있으면 홈 상단 캐러셀에도 실린다. PUT/DELETE /admin/notices/{id}/image로 관리.
    image_url: Mapped[str | None] = mapped_column(String(500), default=None)

    # 노출 기간. 둘 다 nullable이고 null은 "제한 없음"이다 — starts_at=None은 즉시부터,
    # ends_at=None은 무기한. 앱은 지금 시각이 이 구간 안인 공지만 본다(routers/notices).
    starts_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    ends_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Mission(Base):
    """이벤트 미션. 운영자가 참여 기간·달성 조건·리워드·내용을 설정한다.

    달성 조건(condition)과 리워드(reward)는 자유 텍스트다 — 자동 판정(런타임)은
    아직 없고, 운영자가 서술하면 앱이 그대로 보여주는 단계다. 자동 판정이
    필요해지면 그때 condition을 타입+목표값으로 구조화한다.
    """

    __tablename__ = "missions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)

    # 자유 텍스트. 예) "제주 동부 코스 3개 완주" / "굿즈 + 포인트 500".
    condition: Mapped[str] = mapped_column(String(500))
    reward: Mapped[str] = mapped_column(String(500))

    # 참여 기간. 둘 다 nullable이고 null은 "제한 없음"이다(공지와 같은 규칙).
    starts_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    ends_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    # 노출 on/off(기간과 별개)와 정렬. 배너와 같은 방식이다.
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class AdminUser(Base):
    """운영 웹에 로그인하는 운영자 계정. 앱 사용자(users)와 완전히 별개다 —
    앱은 소셜 로그인 전용이라 비밀번호가 없고, 운영자는 아이디/비밀번호로 로그인한다.

    가입 API는 없다. 운영자는 소수라 tools/create_admin.py로 직접 시드한다.
    disabled_at을 채우면 로그인·기존 세션이 모두 막힌다(계정 비활성화).
    """

    __tablename__ = "admin_users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    # bcrypt 해시(app/admin/security.py). 평문은 어디에도 저장하지 않는다.
    password_hash: Mapped[str] = mapped_column(String(100))
    display_name: Mapped[str | None] = mapped_column(String(100), default=None)
    # 채워지면 비활성 계정 — 로그인 거부 + 기존 세션 무효(require_admin_session).
    disabled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class AdminSession(Base):
    """운영자 로그인 세션 1개. 로그인 시 발급, 로그아웃/만료 시 무효화한다.

    쿠키에는 불투명 랜덤 토큰이 실리고, 여기엔 그 토큰의 sha256 해시만 저장한다
    (비밀번호와 같은 논리 — DB가 유출돼도 원본 세션 토큰은 드러나지 않는다).
    앱의 RefreshToken과 같은 패턴이되, 쿠키 기반이라 별도 테이블로 둔다.
    """

    __tablename__ = "admin_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    admin_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("admin_users.id"), index=True
    )
    # 쿠키 토큰의 sha256 hex(64자). 조회 키라 unique + index.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
