import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Numeric,
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
    # 탈퇴 시 Apple 쪽 연결을 끊는(revoke) 데 쓰는 refresh 토큰(app/apple_auth.py).
    # 로그인 때 authorization code를 교환해 채운다. 탈퇴 시 함께 지운다.
    apple_refresh_token: Mapped[str | None] = mapped_column(Text, default=None)
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


# 코스 카테고리. 아트런·로드런·트레일런·챌린지런. 값을 늘리면 schemas.CourseCategory와
# ck_courses_category(마이그레이션)도 같이 바꾼다.
COURSE_CATEGORIES: tuple[str, ...] = ("art", "road", "trail", "challenge")


class Course(Base):
    """관리자가 코스 명단(courses/courses.yaml)을 기준으로 올리는 러닝 코스.

    컬럼은 명단 시트가 가진 항목과 1:1이다. 코스 수정이나 재업로드를 코드로
    다루지 않는다 — 고칠 일이 생기면 DB에서 직접 고치거나 다시 올린다.
    """

    __tablename__ = "courses"
    __table_args__ = (
        CheckConstraint(
            "category IN ('art', 'road', 'trail', 'challenge')", name="ck_courses_category"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    name: Mapped[str] = mapped_column(String(200))

    # 필수. COURSE_CATEGORIES 중 하나(DB CHECK로도 막는다). 태그와 별개로 코스를 크게 나눈다.
    category: Mapped[str] = mapped_column(String(20))

    # 'public' | 'admin'. admin이면 role='admin'인 앱 사용자에게만 내려간다(테스트
    # 코스). 기본값 없음 — NULL은 공개가 아니라서 일반 사용자에게 보이지 않는다.
    visibility: Mapped[str | None] = mapped_column(String(20), default=None)

    # 왕복 기준 km, 소수 첫째 자리까지(예: 8.3). GPX 실측이 아니라 명단에 적힌
    # 안내값이다. 러닝 진행률처럼 정확도가 필요한 계산은 이 값이 아니라 path에서
    # 직접 거리를 재서 쓴다. asdecimal=False라 파이썬에서는 float로 다룬다.
    distance_km: Mapped[float] = mapped_column(Numeric(5, 1, asdecimal=False))

    # 1=★, 2=★★, 3=★★★ — 클라이언트 CourseDifficulty.value와 값이 같아야 한다.
    difficulty: Mapped[int] = mapped_column(SmallInteger)

    # "해안도로,제주시,동쪽" 처럼 쉼표로 이어 붙인다. 태그로 코스를 걸러내는
    # 화면이 아직 없어서 별도 테이블이나 배열 타입까지 갈 이유가 없었다.
    tags: Mapped[str | None] = mapped_column(String(200), default=None)

    address: Mapped[str] = mapped_column(String(300))

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

    # 썸네일 말고 더 보여 줄 이미지(public URL, 보여 줄 순서대로). 전용 엔드포인트
    # (POST/PUT /admin/courses/{id}/images)만 바꾼다.
    image_urls: Mapped[list] = mapped_column(JSONB, default=list)

    path: Mapped[list] = mapped_column(JSONB, default=list)

    # 업로드한 GPX 파일 바이트 그대로. path는 리샘플본이라 원본 점이 남지 않아서
    # 따로 둔다 — 판정·지도는 path만 보고, 이건 GPX 내려받기(GET /courses/{id}/gpx)
    # 전용이다. 원본 없이 올라간 옛 코스는 NULL.
    #
    # deferred: 코스 목록 같은 일반 조회가 파일 바이트까지 끌어오지 않게, 이 속성에
    # 접근할 때만 따로 읽는다.
    original_gpx: Mapped[bytes | None] = mapped_column(
        LargeBinary, default=None, deferred=True
    )

    created_by: Mapped[str | None] = mapped_column(String(100), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # 이 코스에 연결된 협력업체(순서대로). 목록 응답이 코스마다 업체를 따로 조회하지
    # 않게 selectin으로 한 번에 불러온다(링크 → 업체는 CoursePartner.partner가 join).
    # 연결을 바꿀 때는 이 컬렉션을 교체한다 — 빠진 링크는 delete-orphan으로 지워진다.
    partner_links: Mapped[list["CoursePartner"]] = relationship(
        order_by="CoursePartner.sort_order",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class Partner(Base):
    """협력업체. 운영 웹에서 따로 관리하고 코스에는 course_partners로 연결한다.

    업체 정보는 여기에만 있다 — 코스에 복사하지 않으므로 고치면 연결된 모든 코스에
    바로 반영되고, 한 업체를 여러 코스에 걸 수 있다.
    """

    __tablename__ = "partners"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200))

    # 한글 주소는 안내용이라 선택이다. 지도 마커는 좌표만 있으면 찍힌다.
    address: Mapped[str | None] = mapped_column(String(300), default=None)
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)

    comment: Mapped[str | None] = mapped_column(Text, default=None)
    # 계정명이나 URL. 서버가 형식을 해석하지 않는다.
    instagram: Mapped[str | None] = mapped_column(String(200), default=None)
    # 예) "러너 인증 시 아메리카노 10% 할인". 쿠폰 혜택처럼 자유 텍스트다.
    benefit: Mapped[str | None] = mapped_column(String(500), default=None)
    # 쿠폰 사용 번호(숫자 4자리, 업체마다 다름). 직원이 유저 폰에 입력하면 이 업체에서
    # 쓴 것으로 처리된다. 비어 있으면 이 업체에서는 쿠폰을 쓸 수 없다. 앱에 내려가지 않는다.
    coupon_pin: Mapped[str | None] = mapped_column(String(4), unique=True, default=None)

    # 목록 카드 썸네일과 상세 갤러리 이미지(순서대로). 코스와 같은 구조, 전용 엔드포인트가 채운다.
    thumbnail_url: Mapped[str | None] = mapped_column(String(500), default=None)
    image_urls: Mapped[list] = mapped_column(JSONB, default=list)

    # 아직 정해지지 않은 부가 정보(영업시간·업종 등)를 담는 자리. 형태가
    # 굳어지면 컬럼으로 승격한다(user_log.detail과 같은 전략).
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class CoursePartner(Base):
    """코스 ↔ 협력업체 연결. 코스나 업체가 지워지면 연결도 함께 지워진다(CASCADE)."""

    __tablename__ = "course_partners"

    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("courses.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # 복합 PK의 두 번째 열이라 PK 인덱스로는 "이 업체가 걸린 코스"를 못 찾는다.
    partner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("partners.id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )
    # 코스 안에서 업체를 보여줄 순서(운영 웹에서 고른 순서).
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    partner: Mapped[Partner] = relationship(lazy="joined")


class CourseCuration(Base):
    """앱 홈 '러닝 코스 큐레이션'에 띄울 코스. 운영 웹 '홈 구성'에서 고른다.

    홈에 나오는 건 몇 개뿐이라 코스 테이블에 컬럼을 두지 않고 고른 것만 행으로 둔다.
    코스가 지워지면 함께 지워진다(CASCADE).
    """

    __tablename__ = "course_curations"

    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("courses.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # 홈에서 보여줄 순서(작을수록 앞).
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    # 운영자가 쓰는 큐레이션 설명. 앱 노출 방식은 아직 정하지 않았다.
    describe: Mapped[str | None] = mapped_column(Text, default=None)
    # 형태 미정 부가 정보(Partner.detail과 같은 전략).
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)


class PartnerCuration(Base):
    """앱 홈 '추천 협력 업체'에 띄울 업체. 운영 웹 '홈 구성'에서 고른다.

    [CourseCuration]과 같은 이유로 따로 둔다. 업체가 지워지면 함께 지워진다(CASCADE).
    """

    __tablename__ = "partner_curations"

    partner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("partners.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # 홈에서 보여줄 순서(작을수록 앞).
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    # 운영자가 쓰는 큐레이션 설명. 앱 노출 방식은 아직 정하지 않았다.
    describe: Mapped[str | None] = mapped_column(Text, default=None)
    # 형태 미정 부가 정보(Partner.detail과 같은 전략).
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)


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


class StampDefinition(Base):
    """스탬프 종류. 도전과제처럼 "조건 종류 + 조건 값"을 데이터로 갖는다.

    판정 코드는 조건 종류마다 한 번만 쓴다(app/stamp_rules.py). 새 스탬프가 기존
    종류로 표현되면 행만 추가하면 되고(개발자가 DB에 직접, 코스 스탬프만 코스 등록 때 자동), 새로운 종류의 조건이 생길 때만 코드를 더한다.
    코스는 조건 값의 하나일 뿐이라 외래키로 묶지 않는다 — 코스를 지우면 그 코스를
    조건으로 가진 스탬프는 노출을 끈다(admin/courses).
    """

    __tablename__ = "stamp_definitions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(100))
    # 획득 조건 안내. 앱이 스탬프 상세·빙고 칸에 그대로 보여준다.
    description: Mapped[str | None] = mapped_column(Text, default=None)
    # 도안(Supabase Storage public URL). PUT/DELETE /admin/stamps/{id}/image가 채운다.
    # 발급 기록은 이 값을 조회 시 참조하므로 도안을 바꾸면 이미 딴 스탬프에도 반영된다.
    image_url: Mapped[str | None] = mapped_column(String(500), default=None)

    # 'course_complete' {"course_id": str}
    # | 'running_week_course' {"running_week_id": str, "course_id": str} (러닝위크 기간에 그 코스 완주)
    # | 'bingo_lines' {"running_week_id": str, "lines": int} | 'manual' {}. stamp_rules.CONDITION_TYPES와 같아야 한다.
    condition_type: Mapped[str] = mapped_column(String(30))
    condition_params: Mapped[dict] = mapped_column(JSONB, default=dict)

    # 지우지 않고 끈다 — 발급 기록이 이 행을 가리킨다.
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Stamp(Base):
    """사용자가 받은 스탬프(발급 기록). 스탬프 종류당 한 번만 받는다."""

    __tablename__ = "stamps"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "stamp_definition_id", name="uq_stamp_user_definition"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(String(100), index=True)
    stamp_definition_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("stamp_definitions.id"), index=True
    )
    # 달려서 받은 스탬프면 그 러닝. 운영자 지급 등은 None.
    run_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("runs.id"), default=None
    )
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    definition: Mapped[StampDefinition] = relationship(lazy="joined")


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


class RunningWeek(Base):
    """러닝위크. 정기적으로 여는 행사 한 회차이고, 5x5 빙고판을 갖는다(#70).

    노출 규칙은 공지와 같다 — starts_at/ends_at은 null이면 "제한 없음", is_active로
    따로 끌 수 있다. 공개 중이면 앱 커뮤니티 상단에 image_url 배너가 뜬다.

    빙고 칸은 이 회차 전용 스탬프(running_week_course)로 채운다. 칸 전용 테이블은 두지 않고
    칸 순서대로 스탬프 종류 id 25개만 담고, 칸이 채워졌는지는 조회 때 발급 기록(stamps)에서
    계산한다. 배열 안 id에는 외래키가 없어서
    저장할 때 서버가 실제 스탬프 종류인지 확인한다(admin/running_weeks).
    """

    __tablename__ = "running_weeks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # 회차(1, 2, …). 러닝위크 전용 스탬프가 몇 회차 것인지 구분하는 데이터이고 앱에는 안 내린다.
    round: Mapped[int] = mapped_column(Integer, unique=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text, default=None)
    # 커뮤니티 상단 배너(Supabase Storage public URL). PUT/DELETE /admin/running-weeks/{id}/image.
    image_url: Mapped[str | None] = mapped_column(String(500), default=None)

    starts_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    ends_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    # 'public' | 'admin'. admin이면 role='admin'인 앱 사용자에게만 내려간다(코스와 같다).
    # 기본 admin — 운영자가 확인한 뒤 공개로 바꾼다.
    visibility: Mapped[str] = mapped_column(String(20), default="admin")

    # 칸 0~24에 놓을 스탬프 종류 id(문자열). 비어 있으면 빙고판을 아직 안 짠 것.
    bingo_stamp_ids: Mapped[list] = mapped_column(JSONB, default=list)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class RunningWeekParticipation(Base):
    """러닝위크 참가 신청. 사용자·회차당 하나이고, 수정은 아직 없다.

    이름·연락처는 개인정보라 동의를 받고, 신청일로부터 1년 뒤 폐기한다. 폐기는 아직
    자동이 아니다 — expires_at이 지난 행을 운영자가 DB에서 직접 지운다. 폼 항목이
    회차마다 바뀔 수 있어 어떤 폼으로 받았는지 form_version을 남긴다.
    """

    __tablename__ = "running_week_participations"
    __table_args__ = (
        UniqueConstraint(
            "running_week_id", "user_id", name="uq_running_week_participation_user"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    running_week_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("running_weeks.id", ondelete="CASCADE"), index=True
    )
    # 토큰 sub(문자열). Stamp/Run과 같다.
    user_id: Mapped[str] = mapped_column(String(100), index=True)

    name: Mapped[str] = mapped_column(String(50))
    phone: Mapped[str] = mapped_column(String(20))
    # 'male' | 'female'
    gender: Mapped[str] = mapped_column(String(10))
    age: Mapped[int] = mapped_column(SmallInteger)
    # 'jeju'(도민) | 'non_jeju'(도외)
    residence: Mapped[str] = mapped_column(String(20))

    form_version: Mapped[int] = mapped_column(SmallInteger, default=1)
    agreed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Event(Base):
    """커뮤니티 이벤트. 그림 한 장(선택)과 게시글이다(#70).

    운영툴에서 등록한다. 본문에 붙여 넣은 링크(https://...)나 [글자](https://...)는
    앱이 눌러서 열 수 있게 그린다. 노출 규칙은 공지와 같다 — starts_at/ends_at은 null이면
    "제한 없음"이고 is_active로 따로 끌 수 있다.

    옛 missions(이벤트 미션, 앱 노출 없이 데이터 0건)를 0033에서 이 테이블로 바꿨다.
    """

    __tablename__ = "events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    # Supabase Storage public URL. PUT/DELETE /admin/events/{id}/image로 관리.
    image_url: Mapped[str | None] = mapped_column(String(500), default=None)

    starts_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    ends_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # 'public' | 'admin'. 러닝위크와 같다 — admin이면 운영자 계정에만 보인다.
    visibility: Mapped[str] = mapped_column(String(20), default="admin")
    # 앱 목록 정렬. 작을수록 위, 같으면 최신순.
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


class UserLog(Base):
    """사용자 행동 로그. 코스 조회·러닝 시작/이탈·배너 클릭 같은 '신호'를 한 테이블에 모은다.

    상태(runs/stamps/favorites)는 각자 테이블에 두고, 여기는 "눌렀다/봤다/그만뒀다"만
    쌓는다. 종류는 log_name으로 구분하고 부가 정보는 detail(JSONB)에 로그마다 다르게
    담는다 — course_id/run_id도 필요한 로그만 detail에 넣는다(app/user_log.py 참고).

    옛 course_views(하루 1회 중복제거)는 log_name='course_detail_open'으로 여기에
    편입됐다. 중복제거는 저장이 아니라 조회 시(user_id·KST 날짜 DISTINCT)에 한다.
    탈퇴해도 행은 지우지 않는다 — user_id는 랜덤 UUID 문자열이라 users에서 PII를
    비우면 익명 활동으로 남는다.
    """

    __tablename__ = "user_log"
    __table_args__ = (
        Index("ix_user_log_name_created", "log_name", "created_at"),
        Index("ix_user_log_user_created", "user_id", "created_at"),
        Index("ix_user_log_session", "session_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # 토큰 sub(문자열, FK 아님) — Stamp/Run/Favorite과 같다. 로그인 전 로그는 null.
    user_id: Mapped[str | None] = mapped_column(String(100), default=None)
    # 앱 실행 단위 식별자(클라 생성). 서버가 직접 쓰는 로그는 null.
    session_id: Mapped[str | None] = mapped_column(String(36), default=None)
    log_name: Mapped[str] = mapped_column(String(50))
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)
    # 'android' | 'ios'
    platform: Mapped[str | None] = mapped_column(String(10), default=None)
    app_version: Mapped[str | None] = mapped_column(String(20), default=None)
    # 서버 수신 시각. 앱이 배치로 보내면 한 묶음이 거의 같은 값을 갖는다.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Coupon(Base):
    """쿠폰 템플릿(종류). 행은 코드(마이그레이션)가 심고 운영툴은 수정만 한다.

    지급 조건은 스탬프처럼 trigger_type으로 가른다(app/coupon_rules.py). 조건이 늘면
    규칙 코드와 행 하나를 같이 더한다 — 운영툴에서 만들어 봤자 지급할 방법이 없다.

    혜택(benefit)은 자유 텍스트다 — 커머스가 없어 서버가 자동 적용하지 않고, 유저가
    협력업체에서 쓰는 증표다. 발급된 쿠폰은 이 템플릿을 라이브 참조하므로(혜택/이름을
    복사하지 않음) 운영자가 나중에 고치면 발급분에도 즉시 반영된다.
    """

    __tablename__ = "coupons"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(String(2000), default=None)
    # 예) "아메리카노 1잔", "굿즈 교환권". 서버가 해석하지 않는다.
    benefit: Mapped[str] = mapped_column(String(500))
    # 유효기간. null이면 무기한. now > valid_until이면 발급분이 '만료'(사용 불가)로 계산된다.
    valid_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    # 'manual' | 'course_complete' | 'bingo_complete'. coupon_rules.TRIGGER_TYPES와 같아야 한다.
    trigger_type: Mapped[str] = mapped_column(String(30), default="manual")
    # 켜져 있을 때만 자동 지급한다. 기본 꺼짐 — 러닝위크 기간에 운영자가 켠다.
    # 이미 발급된 쿠폰은 꺼도 그대로 쓸 수 있다.
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # 쓸 수 있는 업체. 비어 있으면 모든 업체.
    partners: Mapped[list["CouponPartner"]] = relationship(
        cascade="all, delete-orphan", lazy="selectin"
    )


class CouponPartner(Base):
    """쿠폰 ↔ 사용 가능 업체. 쿠폰이나 업체가 지워지면 연결도 지워진다(CASCADE)."""

    __tablename__ = "coupon_partners"

    coupon_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coupons.id", ondelete="CASCADE"),
        primary_key=True,
    )
    partner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("partners.id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )


class UserCoupon(Base):
    """유저에게 발급된 쿠폰 한 장. 템플릿(coupons)을 라이브 참조한다.

    used_at이 있으면 사용완료, expired_at이 있으면 만료, 둘 다 없으면 사용 가능.
    만료는 coupons.valid_until이 지난 걸 서버가 알아챈 시점(내 쿠폰 조회·사용 시도)에
    expired_at으로 남긴다. 그 전이라도 valid_until이 지났으면 만료로 취급한다.

    user_id는 Stamp/Run/Favorite과 같게 토큰 sub(문자열)를 담는다(FK 아님).
    """

    __tablename__ = "user_coupons"
    __table_args__ = (
        UniqueConstraint("coupon_id", "user_id", "grant_key", name="uq_user_coupon_grant"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    coupon_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("coupons.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(String(100), index=True)
    # 자동 발급의 중복 방지 키(코스완료: "course:{course_id}", 빙고판 완성: "bingo:{week_id}").
    # 운영자 수동 지급은 None.
    grant_key: Mapped[str | None] = mapped_column(String(100), default=None)
    # 달려서 받은 쿠폰이면 그 러닝. 완주 결과 화면이 "이번에 받은 쿠폰"을 찾는 데 쓴다.
    run_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("runs.id", ondelete="SET NULL"), default=None
    )
    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    expired_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    # 어느 업체에서 썼는지. 업체가 지워지면 None으로 남는다.
    used_partner_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("partners.id", ondelete="SET NULL"),
        default=None,
        index=True,
    )
