"""운영 시나리오. 참가자의 행동이 아니라 운영자 설정이나 시스템 동작에 따라 결과가 달라지는 경우다.
운영자가 실수하기 쉬운 지점(쿠폰 활성화를 잊음, 빙고판을 안 짬 등)을 지킨다.
"""

from scenario_flow import (
    ENTRY,
    GEN_SKIP,
    GEN_WIN,
    LINES,
    NO_LINES,
    NOT_FULL,
    REW_NONE,
    REW_SOLD,
    REW_WIN,
)
from scenario_model import (
    BASIC,
    GEN,
    R1,
    R5,
    RW,
    AdminIssue,
    Complete,
    Prefill,
    Scenario,
    Setup,
    SetCoupon,
    sold_out,
)

WIN = {"win": 100}
_GROUP = "운영 시나리오"
_FOUR_ROWS = list(range(20))  # 가로 0~3번 줄. 여기에 20번 칸을 채우면 세로 0번 줄까지 5줄

O = [
    Scenario(
        "O1", _GROUP, "러닝위크 회차가 비활성화되어 있음",
        "참가 신청은 했지만 운영자가 회차를 비활성화해 두었다.",
        Setup(week="inactive"),
        [Complete(0, gets=[BASIC], note="기간 안이어도 러닝위크 보상은 없다")],
        nodes=ENTRY + ("X_rw",),
    ),
    Scenario(
        "O2", _GROUP, "일반 쿠폰을 활성화하지 않음",
        "운영자가 일반 쿠폰을 활성화하지 않은 채 참가자가 새 코스를 완주한다.",
        Setup(),
        [Complete(0, gets=[BASIC, RW], note="쿠폰도, 추첨 기록도 없다")],
        nodes=GEN_SKIP + NO_LINES,
    ),
    Scenario(
        "O3", _GROUP, "빙고판 배치를 하지 않음",
        "운영자가 빙고판을 짜지 않은 회차에서 참가자가 가로 한 줄에 해당하는 코스를 완주한다.",
        Setup(bingo=False, line_stamps=(1, 12), coupons={"general": WIN}),
        [
            Prefill([1, 2, 3, 4]),
            Complete(0, gets=[BASIC, RW, GEN], note="빙고 보상만 건너뛰고 스탬프·일반 쿠폰은 정상"),
        ],
        nodes=GEN_WIN + ("D_layout", "X_nolayout"),
    ),
    Scenario(
        "O4", _GROUP, "리워드를 나중에 활성화",
        "리워드가 비활성화된 채 참가자가 첫 줄을 완성하고, 운영자가 활성화한 뒤 참가자가 다른 코스를 완주한다.",
        Setup(),
        [
            Prefill([0, 1, 2, 3]),
            Complete(4, gets=[BASIC, RW], note="비활성화되어 있으면 기록 없이 건너뛴다"),
            SetCoupon("r1", active=True, win=100, note="운영툴에서 리워드를 활성화"),
            Complete(5, gets=[BASIC, RW, R1], note="다음 완주에서 1줄 기준을 추첨한다"),
        ],
        nodes=GEN_SKIP + LINES + REW_NONE + REW_WIN + NOT_FULL,
    ),
    Scenario(
        "O5", _GROUP, "운영자 수동 발급이 리워드 수량을 차지함",
        "5줄 리워드 수량 1개를 운영자가 수동으로 발급한 뒤, 참가자가 5줄에 도달한다.",
        Setup(coupons={"r5": {"win": 100, "stock": 1}}),
        [
            AdminIssue("r5", 1),
            Prefill(_FOUR_ROWS),
            Complete(20, gets=[BASIC, RW, sold_out(R5)], note="수량이 이미 찼으므로 소진"),
        ],
        nodes=GEN_SKIP + LINES + REW_SOLD + NOT_FULL,
    ),
    Scenario(
        "O6", _GROUP, "앱이 같은 인증을 두 번 보냄",
        "참가자의 같은 완주 인증 요청이 두 번 들어온다(앱 재시도).",
        Setup(),
        [Complete(0, twice=True, gets=[BASIC, RW], note="두 번째 요청은 이전 결과를 그대로 돌려준다")],
        nodes=GEN_SKIP + NO_LINES + ("X_dup",),
    ),
]

SCENARIOS = O
