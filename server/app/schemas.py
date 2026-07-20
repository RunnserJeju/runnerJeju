import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# 필드 이름은 Flutter 클라이언트의 fromJson/toJson과 1:1로 맞춘다.
# 이름을 바꾸면 앱이 조용히 깨지므로 양쪽을 같이 수정해야 한다.

Difficulty = Literal["easy", "normal", "hard"]
VerificationStatusName = Literal[
    "pending", "inProgress", "matched", "mismatched", "failed"
]


class GeoPointSchema(BaseModel):
    lat: float
    lng: float
    altitude: float | None = None
    recorded_at: datetime | None = None


# --- 코스 ---------------------------------------------------------------


class CourseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = None
    region: str | None = None
    difficulty: Difficulty = "normal"
    distance_meters: float
    path: list[GeoPointSchema]


class CourseSummary(BaseModel):
    """목록용. 경로 좌표까지 모두 내려준다(앱에서 미리보기를 그릴 수 있게)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    description: str | None
    region: str | None
    difficulty: Difficulty
    distance_meters: float
    estimated_duration_sec: int | None
    elevation_gain_meters: float | None
    thumbnail_url: str | None
    path: list[GeoPointSchema]
    completed_count: int
    is_completed_by_me: bool


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
    region: str | None
    acquired_at: datetime
    image_url: str | None
    record_id: uuid.UUID | None
