import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

# 필드 이름은 Flutter 클라이언트의 fromJson/toJson과 1:1로 맞춘다.
# 이름을 바꾸면 앱이 조용히 깨지므로 양쪽을 같이 수정해야 한다.

# 1=★, 2=★★, 3=★★★ — 클라이언트 CourseDifficulty.value와 값이 같아야 한다.
Difficulty = Annotated[int, Field(ge=1, le=3)]
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


# --- 배너 -----------------------------------------------------------------


class BannerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    image_url: str
    sort_order: int
    created_at: datetime


# --- 공지사항 -------------------------------------------------------------


class NoticeCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1)


class NoticeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    body: str
    created_at: datetime
