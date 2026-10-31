"""시나리오를 적는 틀. 시나리오는 코드가 아니라 데이터다 — 실행기는 scenario_runner 하나.

시나리오 하나는 이야기 하나다: 상황(Setup) → 사건(events, 순서대로) → 각 사건에서 새로 받은 것(gets).
기대 결과는 구현을 베끼지 않고 사람이 직접 적는다.
"""

from dataclasses import dataclass, field

# 받은 것의 이름. 실행기가 DB에서 같은 이름으로 읽어 와 비교한다.
BASIC = "기본 스탬프"
RW = "러닝위크 스탬프"
GEN = "일반 쿠폰"
SPECIAL = "스페셜 쿠폰"
R1 = "1줄 리워드"
R3 = "3줄 리워드"
R5 = "5줄 리워드"


def line_stamp(lines: int) -> str:
    return f"빙고 {lines}줄 스탬프"


def lost(label: str) -> str:
    """추첨했지만 떨어진 것. 추첨 기록은 남는다."""
    return f"낙첨:{label}"


def sold_out(label: str) -> str:
    """수량이 없어 지급하지 못한 것. 소진 기록이 남는다."""
    return f"소진:{label}"


# 쿠폰 종류 키. Setup.coupons의 키이자 SetCoupon·AdminIssue가 가리키는 대상.
COUPON_KEYS = ("general", "special", "r1", "r3", "r5")


@dataclass(frozen=True)
class Setup:
    """시작 상황. 적지 않은 것은 기본값이다.

    - week: open(공개 중) | inactive(비활성화) | before(기간 전) | after(기간 후)
    - participates: 시작할 때 참가 신청이 되어 있는지(사용자 "me")
    - bingo: 빙고판 25칸 배치가 되어 있는지
    - line_stamps: 만들어 둘 빙고 줄 스탬프의 기준 줄 수
    - coupons: 활성화할 쿠폰. 적은 것만 활성화되고 나머지는 비활성화된다.
      값은 {"win": 확률%(기본 100), "stock": 수량(기본 무제한)}
    """

    week: str = "open"
    participates: bool = True
    bingo: bool = True
    line_stamps: tuple[int, ...] = ()
    coupons: dict = field(default_factory=dict)


@dataclass(frozen=True)
class Complete:
    """코스 완주 인증 한 번. course는 0~24(빙고 칸 번호와 같다)."""

    course: int
    who: str = "me"
    matched: bool = True
    twice: bool = False  # 같은 인증을 두 번 요청한다
    gets: list | None = None  # 이 사건에서 새로 받은 것(순서 무관). None이면 비교하지 않는다
    note: str = ""


@dataclass(frozen=True)
class Join:
    """러닝위크 참가 신청."""

    who: str = "me"
    note: str = ""


@dataclass(frozen=True)
class Prefill:
    """칸을 미리 채운다. 그 칸들의 코스를 실제로 차례로 완주한다 — 그동안 받았을 스탬프·쿠폰·추첨도
    실제로 일어난다. 이 사건에서 받은 것은 비교하지 않는다."""

    cells: list
    who: str = "me"
    note: str = ""


@dataclass(frozen=True)
class SetCoupon:
    """쿠폰 설정을 중간에 바꾼다(운영툴에서 활성화하거나 확률·수량을 바꾸는 것)."""

    key: str
    active: bool | None = None
    win: int | None = None
    stock: int | None = None
    note: str = ""


@dataclass(frozen=True)
class AdminIssue:
    """운영자가 쿠폰을 수동 발급한다(다른 사용자 count명에게)."""

    key: str
    count: int
    note: str = ""


Event = Complete | Join | Prefill | SetCoupon | AdminIssue


@dataclass(frozen=True)
class Scenario:
    id: str
    group: str
    name: str
    situation: str  # 사람이 읽는 한 줄 설명
    setup: Setup
    events: list
    nodes: tuple = ()  # 플로우차트에서 이 시나리오가 지나는 노드("그림번호:노드"). 손으로 단다
