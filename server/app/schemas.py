import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

# 필드 이름은 Flutter 클라이언트의 fromJson/toJson과 1:1로 맞춘다.
# 이름을 바꾸면 앱이 조용히 깨지므로 양쪽을 같이 수정해야 한다.

# 1=★, 2=★★, 3=★★★ — 클라이언트 CourseDifficulty.value와 값이 같아야 한다.
Difficulty = Annotated[int, Field(ge=1, le=3)]

# 'public'=모두, 'admin'=role='admin'인 앱 사용자만(테스트 코스).
CourseVisibility = Literal["public", "admin"]
VerificationStatusName = Literal[
    "pending", "inProgress", "matched", "mismatched", "failed"
]


# 좌표 한 점을 코스와 러닝이 따로 쓴다. 두 경로는 만들어지는 방식도, 실리는
# 값도 겹치지 않아서 한 스키마로 묶으면 양쪽 다 남의 필드를 달고 다니게 된다.
# (코스: 서버가 GPX로 만들어 내려주기만 함 / 러닝: 앱이 GPS로 모아 올림)


class CoursePointSchema(BaseModel):
    """코스 경로의 점."""

    lat: float
    lng: float

    # GPX <ele>에서 온 고도(m). 코스 상세의 고도 그래프가 유일한 소비처다.
    # 원본 GPX의 고도가 온전하지 않으면 서버가 통째로 버리므로 없을 수 있다(app/gpx.py).
    altitude: float | None = None


class RunPointSchema(BaseModel):
    """러닝 기록 경로의 점.

    고도는 담지 않는다. 화면에 보여주지도, 거리·페이스·검증에 쓰지도 않아서
    앱이 아예 수집하지 않는다(Flutter LocationService._toGeoPoint 참고).
    """

    lat: float
    lng: float
    recorded_at: datetime | None = None

    # 이 점 앞에서 기록이 끊겼는지(일시정지 동안 이동한 구간). 검증이 그 구간을
    # 빼고 재는 근거가 된다 — verification.to_segments 참고.
    segment_break: bool = False


# --- 인증 ----------------------------------------------------------------


class KakaoLoginRequest(BaseModel):
    """카카오 SDK 로그인으로 받은 accessToken을 그대로 전달받는다."""

    access_token: str


class AppleLoginRequest(BaseModel):
    """Sign in with Apple로 받은 identityToken(애플 서명 JWT)을 전달받는다.

    email은 애플이 최초 인가 시에만 내려주므로 없을 수 있다.
    """

    identity_token: str
    email: str | None = None
    # 탈퇴 시 Apple 연결 해제용 refresh 토큰을 얻기 위한 1회용 코드. 앱이 함께 보낸다.
    authorization_code: str | None = None


class GoogleLoginRequest(BaseModel):
    """Google Sign-In으로 받은 idToken(구글 서명 JWT)을 전달받는다.

    email/sub 등은 idToken 클레임에 항상 포함돼 있어 애플과 달리 별도 필드로
    받을 필요가 없다.
    """

    id_token: str


class RefreshRequest(BaseModel):
    refresh_token: str


class NicknameUpdate(BaseModel):
    nickname: str = Field(min_length=1, max_length=20)


class UserOut(BaseModel):
    """현재 로그인한 사용자. 앱이 admin 전용 UI를 보일지 정하는 데 쓴다.

    권한 판정 자체는 서버가 `require_admin`으로 하고, 여기서 내려주는 role은
    "보여줄지 말지"를 정하는 용도다. 이 값을 위조해도 서버가 403으로 막는다.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    nickname: str | None
    email: str | None
    profile_image_url: str | None
    role: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    # 닉네임이 아직 없으면(=최초 로그인) 클라이언트가 닉네임 설정 화면으로 보낸다.
    needs_nickname: bool


class AccessTokenOut(BaseModel):
    access_token: str


# --- 운영자 인증 --------------------------------------------------------
# 앱 로그인(위)과 완전히 별개. 운영 웹에서만 쓰며, 세션 쿠키로 인증한다.


class AdminLoginRequest(BaseModel):
    username: str
    password: str


class AdminIdentityOut(BaseModel):
    """로그인·세션 확인(GET /admin/auth/me) 응답. 비밀번호/해시는 절대 담지 않는다."""

    username: str
    display_name: str | None


# --- 코스 ---------------------------------------------------------------


class Facility(BaseModel):
    """주차장/화장실 한 곳. courses.parkings/restrooms JSONB의 원소 하나와 1:1이고,
    Flutter CourseFacility.fromJson/toJson과도 1:1이다.

    lat/lng는 필수다 — 등록 화면의 "확인"(GET /geo/geocode)으로 좌표를 채운 뒤
    보내야 한다는 뜻이다. 좌표 없이 주소만 오면 422로 거른다.
    """

    model_config = ConfigDict(from_attributes=True)

    # 표시용 이름(예: "송악산 공영주차장"). 없으면 주소만 보여준다.
    name: str | None = None
    address: str = Field(min_length=1)
    lat: float
    lng: float


class CourseListItem(BaseModel):
    """목록용. 카드에 필요한 것만 담고 경로 좌표는 뺀다.

    좌표는 코스 하나에 수백 개라 목록 응답을 가장 크게 만드는데, 목록 화면은
    지도를 그리지 않고 카드를 눌러도 상세를 다시 받아온다. 목록에서 미리보기를
    그리게 되면 전체 좌표 대신 줄인 좌표를 따로 내리는 편이 낫다.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    distance_km: int
    difficulty: Difficulty

    # "해안도로,제주시,동쪽" — 칩으로 쪼개는 건 클라이언트가 한다.
    tags: str | None

    address: str

    # 옛 단일 주소 필드. parkings/restrooms(아래)로 대체되는 중이라 새 코스에선
    # 늘 None이다 — 옛 코스와의 호환을 위해 컬럼 drop(0010) 전까지만 남겨둔다.
    parking_address: str | None
    restroom_address: str | None

    # 코스당 여러 개. 각 원소는 좌표까지 포함(app/geocoding.py로 변환해 저장).
    parkings: list[Facility]
    restrooms: list[Facility]

    description: str | None

    # 예상 소요시간(분). 명단에 없으면 None.
    estimated_time_min: int | None

    # 대표 썸네일 public URL. 전용 엔드포인트로만 설정/삭제된다(등록·수정 폼과 별개).
    thumbnail_url: str | None

    # 이 코스 완주 시 주는 스탬프 도안 public URL. 스탬프 앨범이 코스 목록만으로
    # 잠긴 칸(미획득)의 목표 도안까지 그릴 수 있게 코스 응답에 함께 내린다.
    stamp_image_url: str | None

    completed_count: int
    is_completed_by_me: bool

    # None은 미설정(시드 스크립트로 올린 코스). 일반 사용자에겐 public만 내려가므로
    # 앱 응답에서는 admin 계정이 아니면 늘 'public'이다.
    visibility: CourseVisibility | None

    # 지도에 코스 라벨을 찍을 좌표. 경로 전체는 위 이유로 빼지만, 점 하나는
    # 목록 크기에 영향이 없으면서 지도 화면이 코스마다 상세를 부르지 않아도
    # 되게 해준다. 경로가 비어 있는 코스면 None이라 지도에서 빠진다.
    start_point: CoursePointSchema | None


class CourseSummary(CourseListItem):
    """상세/등록 응답. 지도에 그릴 경로 좌표까지 포함한다."""

    path: list[CoursePointSchema]


class CourseUpdate(BaseModel):
    """코스 수정(PATCH /courses/{id}) 요청. **메타데이터만** 바꾼다.

    경로(path)는 여기 없다 — GPX로 정해지고, 이미 그 코스를 달린 사람의 검증·진행률
    기준이라 수정 대상에서 뺐다. 등록 화면과 같은 필드를 쓰므로 값 규칙도 같다.

    썸네일(thumbnail_url)도 여기 없다 — 파일 업로드가 필요해 전용 엔드포인트
    (PUT/DELETE /courses/{id}/thumbnail)가 따로 맡는다.
    """

    name: str = Field(min_length=1)
    distance_km: int = Field(ge=1)
    difficulty: Difficulty
    visibility: CourseVisibility
    address: str = Field(min_length=1)
    tags: str | None = None
    description: str | None = None
    # 예상 소요시간(분). 지우려면 명시적으로 null을 보낸다.
    estimated_time_min: int | None = Field(default=None, ge=1)
    parkings: list[Facility] = Field(default_factory=list)
    restrooms: list[Facility] = Field(default_factory=list)


# --- 지오코딩 ------------------------------------------------------------


class GeocodeResult(BaseModel):
    """주소 후보 하나. 필드는 geocoding.GeocodeResult(dataclass)와 1:1이다."""

    model_config = ConfigDict(from_attributes=True)

    # 지번 주소(항상 있음), 도로명 주소(카카오가 매칭했을 때만).
    address: str
    road_address: str | None
    lat: float
    lng: float


class GeocodeResponse(BaseModel):
    """빈 results는 '주소를 못 찾음'이다 — 호출 실패(502)와 구분된다."""

    results: list[GeocodeResult]


# --- 러닝 기록 ------------------------------------------------------------


class RunCreate(BaseModel):
    course_id: uuid.UUID | None = None
    started_at: datetime
    ended_at: datetime
    distance_meters: float
    duration_sec: int
    path: list[RunPointSchema]


class RunOut(BaseModel):
    id: uuid.UUID
    course_id: uuid.UUID | None
    course_name: str | None
    started_at: datetime
    ended_at: datetime
    distance_meters: float
    duration_sec: int
    path: list[RunPointSchema]


class RunUploadResult(BaseModel):
    record: RunOut

    # 스탬프는 검증(POST /runs/{id}/verification) 결과로만 발급되므로 여기서는 항상 None이다.
    # 필드를 남겨둔 이유는 클라이언트가 이미 이 키를 읽고 있고, 나중에 검증이
    # 동기로 끝나는 경로가 생기면 다시 채울 수 있기 때문이다.
    earned_stamp_id: uuid.UUID | None = None


# --- 검증 ----------------------------------------------------------------


class VerificationCreate(BaseModel):
    course_id: uuid.UUID


class VerificationOut(BaseModel):
    id: uuid.UUID
    run_id: uuid.UUID
    course_id: uuid.UUID
    status: VerificationStatusName
    match_rate: float | None
    detail: str | None
    completed_at: datetime | None

    # 검증이 matched면 이때 발급된 스탬프 id. 앱은 이 값으로 스탬프를 조회한다.
    earned_stamp_id: uuid.UUID | None = None


# --- 스탬프 --------------------------------------------------------------


class StampOut(BaseModel):
    id: uuid.UUID
    course_id: uuid.UUID
    course_name: str
    acquired_at: datetime
    image_url: str | None
    record_id: uuid.UUID | None


# --- 공지사항 -------------------------------------------------------------


class NoticeCreate(BaseModel):
    """공지 작성. 노출 기간은 생략 가능하며 null은 '제한 없음'이다."""

    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1)
    starts_at: datetime | None = None
    ends_at: datetime | None = None

    @model_validator(mode="after")
    def _check_period(self):
        # 종료가 시작보다 빠르면 아무 때도 노출되지 않는 죽은 공지가 된다 — 미리 막는다.
        if self.starts_at and self.ends_at and self.ends_at < self.starts_at:
            raise ValueError("노출 종료가 시작보다 빠를 수 없어요.")
        return self


class NoticeUpdate(NoticeCreate):
    """공지 수정(PATCH /admin/notices/{id}). 작성과 같은 필드로 전체를 교체한다."""


class NoticeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    body: str
    # 있으면 앱이 홈 상단 배너로도 그린다. 이미지는 전용 엔드포인트로 올린다.
    image_url: str | None
    starts_at: datetime | None
    ends_at: datetime | None
    created_at: datetime


# --- 미션 -----------------------------------------------------------------


class MissionCreate(BaseModel):
    """이벤트 미션 작성. 달성 조건·리워드는 자유 텍스트로 서술한다(자동 판정 없음).

    참여 기간(starts_at/ends_at)은 생략 가능하며 null은 '제한 없음'이다.
    """

    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1)
    condition: str = Field(min_length=1, max_length=500)
    reward: str = Field(min_length=1, max_length=500)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    is_active: bool = True
    sort_order: int = 0

    @model_validator(mode="after")
    def _check_period(self):
        # 종료가 시작보다 빠르면 아무 때도 참여할 수 없는 죽은 미션이 된다 — 미리 막는다.
        if self.starts_at and self.ends_at and self.ends_at < self.starts_at:
            raise ValueError("참여 종료가 시작보다 빠를 수 없어요.")
        return self


class MissionUpdate(MissionCreate):
    """미션 수정(PATCH /admin/missions/{id}). 작성과 같은 필드로 전체를 교체한다."""


class MissionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    body: str
    condition: str
    reward: str
    starts_at: datetime | None
    ends_at: datetime | None
    is_active: bool
    sort_order: int
    created_at: datetime


# --- 회원 (운영자 조회) ---------------------------------------------------
# 운영 웹이 가입 회원을 조회한다. 조회 전용 — 상태/제재/러닝은 범위 밖.
# "완주 코스 = 획득 스탬프"다(스탬프는 코스 완주로만, 유저·코스당 1개 발급).


class CompletedCourseOut(BaseModel):
    """상세에서 보여줄 완주 코스 하나(=획득 스탬프 하나)."""

    course_id: uuid.UUID
    name: str
    acquired_at: datetime


class UserSummaryOut(BaseModel):
    """회원 목록의 한 행. 내부 식별자(kakao_id 등) 원본은 담지 않고 가입 provider
    종류만 파생해 준다."""

    id: uuid.UUID
    nickname: str | None
    # 가입에 쓰인 소셜 provider. 보통 하나: ["kakao"] / ["apple"] / ["google"].
    providers: list[str]
    email: str | None
    created_at: datetime
    # 완주 코스 수 = 획득 스탬프 수.
    completed_count: int


class UserDetailOut(BaseModel):
    """회원 상세 — 기본정보 + 완주(스탬프) 코스 목록."""

    id: uuid.UUID
    nickname: str | None
    providers: list[str]
    email: str | None
    profile_image_url: str | None
    created_at: datetime
    completed_count: int
    completed_courses: list[CompletedCourseOut]


class UserListOut(BaseModel):
    """회원 목록 응답. total은 필터 적용된 전체 개수(offset 페이지네이션 UI용)."""

    total: int
    items: list[UserSummaryOut]


# --- 이용 통계 (운영자) ---------------------------------------------------
# 완주·찜·이용자·회원·조회수를 집계한다. registered/active는 탈퇴자 제외(현재),
# 누적 활동·코스 지표는 탈퇴자 포함(역사적 누적).


class StatsOverviewOut(BaseModel):
    """사이트 전체 요약."""

    # 탈퇴자 제외(현재 기준).
    registered_users: int
    # 러닝 1회 이상 한 고유 사용자(탈퇴자 제외).
    active_users: int
    # 누적 총계(탈퇴자 포함).
    total_runs: int
    total_completions: int
    total_favorites: int
    total_views: int


class CourseStatsOut(BaseModel):
    """코스별 이용 지표 한 행. completed_count = 완주자 수 = 획득 스탬프 수."""

    id: uuid.UUID
    name: str
    address: str
    completed_count: int
    favorite_count: int
    # 그 코스를 달린 고유 사용자(완주자의 상위 집합).
    runner_count: int
    # 코스별 조회수(하루 1회 중복제거한 고유 조회).
    view_count: int


# --- 쿠폰 (운영자 + 앱) ----------------------------------------------------
# 템플릿(coupons) + 발급 인스턴스(user_coupons). 혜택은 자유텍스트, 발급분은 템플릿을
# 라이브 참조(수정 즉시 반영). 상태는 used_at으로, '만료'는 valid_until로 계산한다.

CouponStatus = Literal["available", "used", "expired"]


class CouponCreate(BaseModel):
    """쿠폰 제작. 혜택은 자유 텍스트, 유효기간은 생략 가능(무기한)."""

    name: str = Field(min_length=1, max_length=200)
    benefit: str = Field(min_length=1, max_length=500)
    description: str | None = None
    valid_until: datetime | None = None


class CouponUpdate(CouponCreate):
    """쿠폰 수정(PATCH). 작성과 같은 필드로 전체 교체한다."""


class CouponOut(BaseModel):
    """운영자 쿠폰 목록/상세. 발급/사용 수를 함께 준다."""

    id: uuid.UUID
    name: str
    description: str | None
    benefit: str
    valid_until: datetime | None
    created_at: datetime
    issued_count: int
    used_count: int


class IssueRequest(BaseModel):
    """대량 지급. 존재하는(비탈퇴) 회원에게만 발급된다."""

    user_ids: list[uuid.UUID] = Field(min_length=1)


class IssueResult(BaseModel):
    issued: int


class IssuedCouponOut(BaseModel):
    """발급 현황 한 행 — 누구에게 발급됐고 사용했는지."""

    id: uuid.UUID  # user_coupon id
    user_id: uuid.UUID
    nickname: str | None  # 탈퇴/미설정이면 null
    issued_at: datetime
    used_at: datetime | None
    status: CouponStatus


class IssuedListOut(BaseModel):
    total: int
    items: list[IssuedCouponOut]


class MyCouponOut(BaseModel):
    """앱: 내 쿠폰 한 장. 혜택·유효기간은 템플릿을 라이브 참조."""

    id: uuid.UUID  # user_coupon id
    name: str
    description: str | None
    benefit: str
    issued_at: datetime
    used_at: datetime | None
    valid_until: datetime | None
    status: CouponStatus
