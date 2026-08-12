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


class GeoPointSchema(BaseModel):
    lat: float
    lng: float
    altitude: float | None = None
    recorded_at: datetime | None = None


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
    parking_address: str | None
    restroom_address: str | None
    description: str | None
    completed_count: int
    is_completed_by_me: bool

    # 지도에 코스 라벨을 찍을 좌표. 경로 전체는 위 이유로 빼지만, 점 하나는
    # 목록 크기에 영향이 없으면서 지도 화면이 코스마다 상세를 부르지 않아도
    # 되게 해준다. 경로가 비어 있는 코스면 None이라 지도에서 빠진다.
    start_point: GeoPointSchema | None


class CourseSummary(CourseListItem):
    """상세/등록 응답. 지도에 그릴 경로 좌표까지 포함한다."""

    path: list[GeoPointSchema]


# --- 러닝 기록 ------------------------------------------------------------


class RunCreate(BaseModel):
    course_id: uuid.UUID | None = None
    started_at: datetime
    ended_at: datetime
    distance_meters: float
    duration_sec: int
    path: list[GeoPointSchema]


class RunOut(BaseModel):
    id: uuid.UUID
    course_id: uuid.UUID | None
    course_name: str | None
    started_at: datetime
    ended_at: datetime
    distance_meters: float
    duration_sec: int
    path: list[GeoPointSchema]


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
