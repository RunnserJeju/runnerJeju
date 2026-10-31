import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# 필드 이름은 Flutter 클라이언트의 fromJson/toJson과 1:1로 맞춘다.
# 이름을 바꾸면 앱이 조용히 깨지므로 양쪽을 같이 수정해야 한다.

# 1=★, 2=★★, 3=★★★ — 클라이언트 CourseDifficulty.value와 값이 같아야 한다.
Difficulty = Annotated[int, Field(ge=1, le=3)]

# 'public'=모두, 'admin'=role='admin'인 앱 사용자만(테스트 코스).
# 공개 범위. admin은 role='admin'인 앱 사용자에게만 내려간다(코스·러닝위크·이벤트 공통).
Visibility = Literal["public", "admin"]
CourseVisibility = Visibility
# 아트런·로드런·트레일런·챌린지런. models.COURSE_CATEGORIES와 같아야 한다.
CourseCategory = Literal["art", "road", "trail", "challenge"]
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
    created_at: datetime


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


class PartnerPayload(BaseModel):
    """협력업체 등록/수정(전체 교체) 요청. POST/PATCH /admin/partners.

    이름과 좌표가 필수, 나머지는 선택이다. 좌표는 지도 마커에 쓰므로 반드시 있어야
    하고, 운영 웹은 주소 "좌표 확인"으로 채우거나 직접 입력한다. 범위 검사는 위도와
    경도를 뒤바꿔 넣는 실수를 거른다.
    """

    name: str = Field(min_length=1, max_length=200)
    address: str | None = Field(default=None, max_length=300)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    comment: str | None = None
    instagram: str | None = Field(default=None, max_length=200)
    benefit: str | None = Field(default=None, max_length=500)
    # 쿠폰 사용 번호. 숫자 4자리, 업체끼리 겹치면 409. 비우면 이 업체에서 쿠폰을 못 쓴다.
    coupon_pin: str | None = Field(default=None, pattern=r"^\d{4}$")
    # 형태 미정인 부가 정보. 서버는 내용을 해석하지 않는다.
    detail: dict = Field(default_factory=dict)


class PartnerSummary(BaseModel):
    """코스 응답에 실리는 협력업체 한 곳. Flutter CoursePartner.fromJson과 1:1이다."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    address: str | None
    lat: float
    lng: float
    comment: str | None
    instagram: str | None
    benefit: str | None
    detail: dict
    # 목록 카드 썸네일. 없으면 앱이 업종 아이콘을 그린다.
    thumbnail_url: str | None = None
    # 상세 갤러리 이미지(순서대로).
    image_urls: list[str] = []

    @field_validator("image_urls", mode="before")
    @classmethod
    def _none_to_empty(cls, value):
        # 아직 flush 안 된 모델이나 옛 행은 None일 수 있다.
        return value or []


class PartnerImagesUpdate(BaseModel):
    """추가 이미지 순서 바꾸기·빼기(PUT /admin/partners/{id}/images). 코스와 같은 규칙."""

    image_urls: list[str]

    @field_validator("image_urls")
    @classmethod
    def _unique(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("같은 이미지가 두 번 들어 있어요.")
        return value


class PartnerCourseRef(BaseModel):
    """협력업체에 연결된 코스 하나(앱 협력업체 시트에서 그 코스로 넘어가는 데 쓴다)."""

    id: uuid.UUID
    name: str


class PartnerWithCourses(PartnerSummary):
    """앱 GET /partners 응답 한 건. 협력업체 모드의 지도·목록 시트가 쓴다."""

    # 이 업체가 연결된 코스(이름순). 사용자에게 보이지 않는 코스는 빠진다.
    courses: list[PartnerCourseRef]


class PartnerOut(PartnerSummary):
    """운영 웹 협력업체 목록/상세 응답."""

    # 이 업체가 연결된 코스 수. 삭제하면 그 코스들에서 빠진다는 경고에 쓴다.
    course_count: int
    # 이 업체에서 사용된 쿠폰 수(업체 이용률).
    coupon_used_count: int = 0
    # 쿠폰 사용 번호. 운영 웹에만 실린다(PartnerSummary에는 없음).
    coupon_pin: str | None = None
    created_at: datetime
    updated_at: datetime


class HomeCurationItem(BaseModel):
    """홈 섹션의 한 칸. id는 섹션에 따라 코스 id 또는 협력업체 id다."""

    id: uuid.UUID
    # 운영자가 쓰는 큐레이션 설명. 앱 노출 방식은 아직 정하지 않았다.
    describe: str | None = None
    # 형태 미정 부가 정보. 서버는 내용을 해석하지 않는다.
    detail: dict = Field(default_factory=dict)


class HomeCurationOut(BaseModel):
    """앱 홈 구성. GET /home/curation(앱), GET /admin/home(운영 웹).

    앞에 있을수록 홈에서 먼저 나온다. 비어 있으면 그 섹션은 앱 홈에서 접힌다.
    """

    # '러닝 코스 큐레이션'에 띄울 코스.
    courses: list[HomeCurationItem]
    # '추천 협력 업체'에 띄울 업체.
    partners: list[HomeCurationItem]


class HomeCurationPayload(BaseModel):
    """홈 섹션 하나의 구성(전체 교체). PUT /admin/home/courses, /admin/home/partners."""

    items: list[HomeCurationItem]


class CourseListItem(BaseModel):
    """목록용. 카드에 필요한 것만 담고 경로 좌표는 뺀다.

    좌표는 코스 하나에 수백 개라 목록 응답을 가장 크게 만드는데, 목록 화면은
    지도를 그리지 않고 카드를 눌러도 상세를 다시 받아온다. 목록에서 미리보기를
    그리게 되면 전체 좌표 대신 줄인 좌표를 따로 내리는 편이 낫다.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    distance_km: float
    difficulty: Difficulty
    category: CourseCategory

    # "해안도로,제주시,동쪽" — 칩으로 쪼개는 건 클라이언트가 한다.
    tags: str | None

    address: str

    # 코스당 여러 개. 각 원소는 좌표까지 포함(app/geocoding.py로 변환해 저장).
    parkings: list[Facility]
    restrooms: list[Facility]

    # 연결된 협력업체(운영 웹에서 고른 순서). 시설처럼 좌표를 포함해 지도 마커로 찍는다.
    partners: list[PartnerSummary]

    description: str | None

    # 예상 소요시간(분). 명단에 없으면 None.
    estimated_time_min: int | None

    # 대표 썸네일 public URL. 전용 엔드포인트로만 설정/삭제된다(등록·수정 폼과 별개).
    thumbnail_url: str | None
    # 썸네일 말고 더 보여 줄 이미지(순서대로). 전용 엔드포인트로만 바뀐다.
    image_urls: list[str] = []

    # 이 코스 완주 스탬프의 도안(스탬프 종류에서 가져옴). 옛 앱 스탬프 탭 호환용 —
    # 새 앱은 GET /stamp-definitions를 쓴다(#71).
    stamp_image_url: str | None = None

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
    # 소수 첫째 자리까지(DB Numeric(5,1)). 0.1 미만·9999.9 초과는 거절.
    distance_km: float = Field(ge=0.1, le=9999.9)
    difficulty: Difficulty
    category: CourseCategory
    visibility: CourseVisibility
    address: str = Field(min_length=1)
    tags: str | None = None
    description: str | None = None
    # 예상 소요시간(분). 지우려면 명시적으로 null을 보낸다.
    estimated_time_min: int | None = Field(default=None, ge=1)
    parkings: list[Facility] = Field(default_factory=list)
    restrooms: list[Facility] = Field(default_factory=list)
    # 연결할 협력업체 id(보여줄 순서대로). 통째로 교체한다 — 빈 목록이면 전부 해제.
    partner_ids: list[uuid.UUID] = Field(default_factory=list)

    @field_validator("distance_km")
    @classmethod
    def _round_distance(cls, value: float) -> float:
        # DB가 Numeric(5,1)로 반올림하기 전에 여기서 맞춰 응답과 저장값이 같게 한다.
        return round(value, 1)


class CourseImagesUpdate(BaseModel):
    """추가 이미지 순서 바꾸기·빼기(PUT /admin/courses/{id}/images). 지금 있는 URL로만."""

    image_urls: list[str]

    @field_validator("image_urls")
    @classmethod
    def _unique(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("같은 이미지가 두 번 들어 있어요.")
        return value


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
    # 이 러닝으로 코스 완주 인증이 통과했는지.
    completed: bool = False


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

    # 이 러닝으로 새로 받은 코스 스탬프 id. 재완주라 새로 받은 게 없으면 None.
    earned_stamp_id: uuid.UUID | None = None
    # 이 러닝으로 새로 받은 코스완료 쿠폰(user_coupon id). 없으면 None.
    earned_coupon_id: uuid.UUID | None = None
    # 이 러닝으로 받은 러닝위크 스탬프(코스 전용 → 빙고 줄 수 순)와 스페셜 쿠폰(빙고판 완성).
    earned_running_week_stamp_ids: list[uuid.UUID] = []
    earned_bingo_coupon_id: uuid.UUID | None = None


# --- 스탬프 --------------------------------------------------------------


class StampDefinitionOut(BaseModel):
    """스탬프 종류. 앱 스탬프 탭이 잠긴 칸까지 그리는 데 쓴다."""

    id: uuid.UUID
    name: str
    description: str | None
    image_url: str | None
    condition_type: str
    # condition_type이 course_complete일 때 그 코스. 앱이 칸을 누르면 코스 안내로 보낸다.
    course_id: uuid.UUID | None
    sort_order: int


class StampOut(BaseModel):
    id: uuid.UUID
    stamp_definition_id: uuid.UUID
    name: str
    description: str | None
    image_url: str | None
    condition_type: str
    course_id: uuid.UUID | None
    acquired_at: datetime
    record_id: uuid.UUID | None
    # 옛 앱 호환. course_name은 스탬프 이름과 같다.
    course_name: str


class StampDefinitionUpdate(BaseModel):
    """스탬프 종류 수정(PATCH /admin/stamps/{id}). 표시 정보만 — 지급 조건은 운영툴에서 안 바꾼다.
    도안은 전용 엔드포인트로 올린다."""

    name: str = Field(min_length=1, max_length=100)
    description: str | None = None
    is_active: bool = True
    sort_order: int = 0


class AdminStampDefinitionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    description: str | None
    # 직접 올린 도안. 등록/교체/삭제는 이걸 기준으로 한다.
    image_url: str | None
    # 앱이 실제로 그리는 도안 — 직접 올린 것이 없으면 코스 카테고리 기본 도안.
    display_image_url: str | None = None
    condition_type: str
    condition_params: dict
    is_active: bool
    sort_order: int
    # 이 스탬프를 받은 사람 수.
    issued_count: int = 0
    created_at: datetime
    updated_at: datetime


# --- 러닝위크 -------------------------------------------------------------

BINGO_SIZE = 5
BINGO_CELLS = BINGO_SIZE * BINGO_SIZE

# 참가 폼 버전. 항목을 바꾸면 올린다 — 신청 행마다 어떤 폼으로 받았는지 남는다.
PARTICIPATION_FORM_VERSION = 1


class BingoCellOut(BaseModel):
    position: int
    # 칸에 놓인 스탬프. 운영자가 숨긴 스탬프면 None(빈 칸).
    stamp: StampDefinitionOut | None
    acquired: bool


class BingoOut(BaseModel):
    cells: list[BingoCellOut]
    # 다 채운 가로·세로·대각선 줄 수(0~12).
    completed_lines: int


class RunningWeekOut(BaseModel):
    """앱용. 빙고판은 참가 신청을 한 사람에게만 내린다."""

    id: uuid.UUID
    title: str
    description: str | None
    image_url: str | None
    starts_at: datetime | None
    ends_at: datetime | None
    participated: bool
    bingo: BingoOut | None


class RunningWeekParticipationCreate(BaseModel):
    """참가 신청. 개인정보 수집·이용 동의(agreed)가 있어야 받는다."""

    name: str = Field(min_length=1, max_length=50)
    phone: str
    gender: Literal["male", "female"]
    age: int = Field(ge=1, le=120)
    residence: Literal["jeju", "non_jeju"]
    agreed: bool

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("이름을 입력해 주세요.")
        return value

    @field_validator("phone")
    @classmethod
    def _normalize_phone(cls, value: str) -> str:
        # 숫자만 남겨 저장한다. 국내 휴대폰·일반 전화 길이(9~11자리)만 받는다.
        digits = "".join(ch for ch in value if ch.isdigit())
        if not 9 <= len(digits) <= 11:
            raise ValueError("연락처를 확인해 주세요.")
        return digits

    @field_validator("agreed")
    @classmethod
    def _must_agree(cls, value: bool) -> bool:
        if not value:
            raise ValueError("개인정보 수집·이용에 동의해야 참가할 수 있어요.")
        return value


class RunningWeekCreate(BaseModel):
    """운영툴 등록·수정. 배너 이미지와 빙고 배치는 전용 엔드포인트로 따로 바꾼다."""

    # 회차. 등록 때 비우면 지금까지 가장 큰 회차 + 1, 수정 때 비우면 그대로.
    round: int | None = Field(default=None, ge=1, le=999)
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    is_active: bool = True
    # 기본 admin — 운영자가 확인한 뒤 공개로 바꾼다.
    visibility: Visibility = "admin"

    @model_validator(mode="after")
    def _check_period(self):
        if self.starts_at and self.ends_at and self.ends_at < self.starts_at:
            raise ValueError("공개 종료가 시작보다 빠를 수 없어요.")
        return self


class RunningWeekUpdate(RunningWeekCreate):
    """수정(PATCH /admin/running-weeks/{id}). 작성과 같은 필드로 전체를 교체한다."""


class BingoUpdate(BaseModel):
    """빙고 배치. 칸 순서대로 스탬프 종류 id 25개, 중복 없이."""

    stamp_ids: list[uuid.UUID] = Field(min_length=BINGO_CELLS, max_length=BINGO_CELLS)

    @field_validator("stamp_ids")
    @classmethod
    def _unique(cls, value: list[uuid.UUID]) -> list[uuid.UUID]:
        if len(set(value)) != len(value):
            raise ValueError("같은 스탬프를 두 칸에 놓을 수 없어요.")
        return value


class AdminRunningWeekOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    round: int
    title: str
    description: str | None
    image_url: str | None
    starts_at: datetime | None
    ends_at: datetime | None
    is_active: bool
    visibility: Visibility
    bingo_stamp_ids: list[str]
    participant_count: int = 0
    created_at: datetime
    updated_at: datetime


class AdminParticipationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: str
    name: str
    phone: str
    gender: str
    age: int
    residence: str
    form_version: int
    agreed_at: datetime
    expires_at: datetime
    created_at: datetime


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


# --- 이벤트 ----------------------------------------------------------------


class EventCreate(BaseModel):
    """이벤트 작성. 이미지는 전용 엔드포인트로 올린다. 기간 null은 '제한 없음'이다."""

    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    is_active: bool = True
    visibility: Visibility = "admin"
    sort_order: int = 0

    @model_validator(mode="after")
    def _check_period(self):
        if self.starts_at and self.ends_at and self.ends_at < self.starts_at:
            raise ValueError("노출 종료가 시작보다 빠를 수 없어요.")
        return self


class EventUpdate(EventCreate):
    """이벤트 수정(PATCH /admin/events/{id}). 작성과 같은 필드로 전체를 교체한다."""


class EventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    body: str
    image_url: str | None
    starts_at: datetime | None
    ends_at: datetime | None
    created_at: datetime


class AdminEventOut(EventOut):
    is_active: bool
    visibility: Visibility
    sort_order: int
    updated_at: datetime


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
    # 최근 행동 로그에 찍힌 기기 종류('ios'/'android'). 로그가 없으면 None.
    platform: str | None
    # 최근 app_open·login 로그의 기기 모델. 없으면 None.
    device: str | None
    created_at: datetime
    last_login_at: datetime | None
    # 완주 코스 수 = 획득 스탬프 수.
    completed_count: int


class UserDetailOut(BaseModel):
    """회원 상세 — 기본정보 + 완주(스탬프) 코스 목록."""

    id: uuid.UUID
    nickname: str | None
    providers: list[str]
    email: str | None
    platform: str | None
    device: str | None
    profile_image_url: str | None
    created_at: datetime
    last_login_at: datetime | None
    completed_count: int
    completed_courses: list[CompletedCourseOut]


class UserListOut(BaseModel):
    """회원 목록 응답. total은 필터 적용된 전체 개수(offset 페이지네이션 UI용)."""

    total: int
    items: list[UserSummaryOut]


# --- 이용 통계 (운영자) ---------------------------------------------------
# 완주·찜·이용자·회원·조회수를 집계한다. registered/active는 탈퇴자 제외(현재),
# 누적 활동·코스 지표는 탈퇴자 포함(역사적 누적).


# --- 쿠폰 (운영자 + 앱) ----------------------------------------------------
# 템플릿(coupons) + 발급 인스턴스(user_coupons). 템플릿 행은 코드가 심고 운영툴은 수정만
# 한다. 발급분은 템플릿을 라이브 참조(수정 즉시 반영). 상태는 used_at(사용) ·
# expired_at(만료, 서버가 알아챈 시점에 저장) · valid_until(아직 저장 전인 만료)로 계산한다.

CouponStatus = Literal["available", "used", "expired"]
CouponTriggerType = Literal["manual", "course_complete", "bingo_complete"]


class CouponUpdate(BaseModel):
    """쿠폰 수정(PATCH). 지급 조건은 못 바꾼다 — 이름·혜택·설명·유효기간·사용 업체·켜고 끄기."""

    name: str = Field(min_length=1, max_length=200)
    benefit: str = Field(min_length=1, max_length=500)
    description: str | None = None
    valid_until: datetime | None = None
    is_active: bool = False
    # 쓸 수 있는 업체. 비우면 모든 업체.
    partner_ids: list[uuid.UUID] = Field(default_factory=list)


class CouponOut(BaseModel):
    """운영자 쿠폰 목록/상세. 발급/사용 수를 함께 준다."""

    id: uuid.UUID
    name: str
    description: str | None
    benefit: str
    valid_until: datetime | None
    trigger_type: CouponTriggerType
    is_active: bool
    partner_ids: list[uuid.UUID]
    created_at: datetime
    issued_count: int
    used_count: int


class IssueRequest(BaseModel):
    """대량 지급. 존재하는(비탈퇴) 회원에게만 발급된다."""

    user_ids: list[uuid.UUID] = Field(min_length=1)


class IssueResult(BaseModel):
    issued: int


class IssuedCouponOut(BaseModel):
    """발급 현황 한 행 — 누구에게 발급됐고 어디서 썼는지."""

    id: uuid.UUID  # user_coupon id
    user_id: uuid.UUID
    nickname: str | None  # 탈퇴/미설정이면 null
    issued_at: datetime
    used_at: datetime | None
    used_partner_name: str | None  # 업체가 지워졌거나 미사용이면 null
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
    # 쓸 수 있는 업체 id. None이면 모든 업체.
    partner_ids: list[uuid.UUID] | None
    used_partner_name: str | None


class CouponUseRequest(BaseModel):
    """쿠폰 사용. 업체 직원이 입력한 업체 고유 번호(Partner.coupon_pin)를 보낸다."""

    pin: str = Field(pattern=r"^\d{4}$")


class UserLogIn(BaseModel):
    """앱이 보내는 행동 로그 한 건. log_name은 app/user_log.LOG_NAMES 안이어야 한다."""

    log_name: Annotated[str, Field(max_length=50)]
    detail: dict = Field(default_factory=dict)
    session_id: Annotated[str, Field(max_length=36)] | None = None
    platform: Literal["android", "ios"] | None = None
    app_version: Annotated[str, Field(max_length=20)] | None = None


class UserLogBatchIn(BaseModel):
    """앱이 몇 초 모았다가 한 번에 보내는 묶음. 빈 묶음은 받지 않는다."""

    logs: Annotated[list[UserLogIn], Field(min_length=1, max_length=100)]


class MetricInfoOut(BaseModel):
    """지표 목록의 한 항목. group은 드롭다운 묶음, group_bys는 지원하는 쪼개기 차원."""

    name: str
    label: str
    group: str
    group_bys: list[str]


class MetricPointOut(BaseModel):
    """지표 값 한 점. key는 group_by에 따라 null(합계)/날짜/코스 id, name은 코스명."""

    key: str | None
    name: str | None
    count: int


class UserLogOut(BaseModel):
    id: uuid.UUID
    log_name: str
    user_id: str | None
    nickname: str | None
    session_id: str | None
    detail: dict
    platform: str | None
    app_version: str | None
    created_at: datetime


class LogNameOut(BaseModel):
    name: str
    label: str
    group: str


class UserLogListOut(BaseModel):
    """원본 로그 페이지. next_cursor가 null이면 마지막 페이지."""

    items: list[UserLogOut]
    next_cursor: str | None
