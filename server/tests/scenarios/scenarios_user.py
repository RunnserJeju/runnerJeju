"""사용자 시나리오. 참가자가 겪는 일을 순서대로 적는다. nodes는 scenario_flow의 흐름도에서 지나는 길이다.

빙고판은 5x5이고 칸 번호는 0~24, 코스 번호와 같다(칸 i = (i+1)번 코스).
  가로 줄 r: r*5 ~ r*5+4   세로 줄 c: c, c+5, c+10, c+15, c+20
  대각선: 0, 6, 12, 18, 24   반대 대각선: 4, 8, 12, 16, 20
Prefill은 그 칸들의 코스를 실제로 완주한 것과 같다(받은 것은 비교하지 않는다).
"""

from scenario_flow import (
    ENTRY,
    FULL_SP_WIN,
    GEN_LOST,
    GEN_SKIP,
    GEN_WIN,
    LINES,
    NO_LINES,
    NOT_FULL,
    REW_LOST,
    REW_NONE,
    REW_SOLD,
    REW_WIN,
)
from scenario_model import (
    BASIC,
    GEN,
    R1,
    R3,
    R5,
    RW,
    SPECIAL,
    Complete,
    Join,
    Prefill,
    Scenario,
    Setup,
    line_stamp,
    lost,
    sold_out,
)

WIN = {"win": 100}  # 추첨 결과를 당첨으로 고정
LOSE = {"win": 0}  # 추첨 결과를 낙첨으로 고정
_LINE_STAMPS = (1, 12)
_ALL_REWARDS = {"r1": WIN, "r3": WIN, "r5": WIN}

A = [
    Scenario(
        "A1", "A. 참가와 완주", "러닝위크 참가 안 한 사람이 코스 완주",
        "러닝위크에 참가 신청을 하지 않은 사람이 1번 코스를 완주한다.",
        Setup(participates=False),
        [Complete(0, gets=[BASIC], note="기본 스탬프만 받는다")],
        nodes=ENTRY + ("X_rw",),
    ),
    Scenario(
        "A2", "A. 참가와 완주", "참가자가 코스를 처음 완주",
        "러닝위크 참가자가 1번 코스를 처음 완주한다.",
        Setup(),
        [Complete(0, gets=[BASIC, RW], note="기본 스탬프와 러닝위크 스탬프를 같이 받는다")],
        nodes=GEN_SKIP + NO_LINES,
    ),
    Scenario(
        "A3", "A. 참가와 완주", "러닝위크 시작 전에 완주",
        "참가 신청은 했지만 러닝위크가 아직 시작되지 않았다.",
        Setup(week="before"),
        [Complete(0, gets=[BASIC])],
        nodes=ENTRY + ("X_rw",),
    ),
    Scenario(
        "A4", "A. 참가와 완주", "러닝위크가 끝난 뒤 완주",
        "참가 신청은 했지만 러닝위크 기간이 끝났다.",
        Setup(week="after"),
        [Complete(0, gets=[BASIC])],
        nodes=ENTRY + ("X_rw",),
    ),
    Scenario(
        "A5", "A. 참가와 완주", "완주하고 나서 참가, 같은 코스를 다시 완주",
        "참가 전에 1번 코스를 완주하고, 러닝위크에 참가한 뒤 같은 코스를 다시 완주한다.",
        Setup(participates=False),
        [
            Complete(0, gets=[BASIC], note="참가 전이라 기본 스탬프만"),
            Join(),
            Complete(0, gets=[RW], note="참가 전 완주는 소급되지 않고, 다시 달려야 러닝위크 스탬프를 받는다"),
        ],
        nodes=ENTRY + ("X_rw",) + GEN_SKIP + NO_LINES,
    ),
    Scenario(
        "A6", "A. 참가와 완주", "코스를 벗어나 달려서 인증 실패",
        "참가자가 코스에서 벗어난 경로로 달린다.",
        Setup(),
        [Complete(0, matched=False, gets=[], note="아무것도 받지 않는다")],
        nodes=("S", "D_dup", "D_match", "X_nomatch"),
    ),
]

B = [
    Scenario(
        "B1", "B. 일반 쿠폰", "완주하고 일반 쿠폰 당첨",
        "참가자가 새 코스를 완주하고 일반 쿠폰 추첨에 당첨된다.",
        Setup(coupons={"general": WIN}),
        [Complete(0, gets=[BASIC, RW, GEN])],
        nodes=GEN_WIN + NO_LINES,
    ),
    Scenario(
        "B2", "B. 일반 쿠폰", "완주했지만 일반 쿠폰 낙첨",
        "참가자가 새 코스를 완주했지만 일반 쿠폰 추첨에서 떨어진다.",
        Setup(coupons={"general": LOSE}),
        [Complete(0, gets=[BASIC, RW, lost(GEN)], note="쿠폰은 없고 낙첨 기록만 남는다")],
        nodes=GEN_LOST + NO_LINES,
    ),
    Scenario(
        "B3", "B. 일반 쿠폰", "쿠폰 받은 코스를 또 달림",
        "1번 코스로 일반 쿠폰을 받은 뒤 같은 코스를 또 완주한다.",
        Setup(coupons={"general": WIN}),
        [
            Complete(0, gets=[BASIC, RW, GEN]),
            Complete(0, gets=[], note="같은 코스로는 더 받지 않는다"),
        ],
        nodes=GEN_WIN + NO_LINES,
    ),
    Scenario(
        "B4", "B. 일반 쿠폰", "낙첨된 코스를 다시 달려도 다시 뽑지 않음",
        "1번 코스에서 일반 쿠폰 낙첨 후 같은 코스를 다시 완주한다.",
        Setup(coupons={"general": LOSE}),
        [
            Complete(0, gets=[BASIC, RW, lost(GEN)]),
            Complete(0, gets=[], note="한 번 추첨한 코스는 다시 뽑지 않는다(낙첨 기록도 새로 생기지 않음)"),
        ],
        nodes=GEN_LOST + NO_LINES,
    ),
]

C = [
    Scenario(
        "C1", "C. 빙고 줄", "빙고 한 줄을 거의 채웠지만 아직",
        "가로 첫 줄 5칸 중 4칸까지 채운다.",
        Setup(line_stamps=_LINE_STAMPS),
        [Prefill([0, 1, 2]), Complete(3, gets=[BASIC, RW], note="줄이 완성되지 않아 줄 스탬프는 없다")],
        nodes=GEN_SKIP + NO_LINES,
    ),
    Scenario(
        "C2", "C. 빙고 줄", "빙고 첫 줄 완성",
        "가로 첫 줄의 마지막 칸을 채운다.",
        Setup(line_stamps=_LINE_STAMPS),
        [Prefill([0, 1, 2, 3]), Complete(4, gets=[BASIC, RW, line_stamp(1)])],
        nodes=GEN_SKIP + LINES + REW_NONE + NOT_FULL,
    ),
]

D = [
    Scenario(
        "D1", "D. 리워드", "첫 줄 완성하고 1줄 리워드 당첨",
        "첫 줄을 완성하고 1줄 리워드 추첨에 당첨된다.",
        Setup(coupons=_ALL_REWARDS),
        [Prefill([0, 1, 2, 3]), Complete(4, gets=[BASIC, RW, R1], note="3줄·5줄 리워드는 아직 해당 없음")],
        nodes=GEN_SKIP + LINES + REW_WIN + NOT_FULL,
    ),
    Scenario(
        "D2", "D. 리워드", "1줄 리워드 낙첨, 계속 달려도 다시 안 뽑힘",
        "첫 줄을 완성했지만 1줄 리워드에서 떨어지고, 이어서 다른 코스를 완주한다.",
        Setup(coupons={"r1": LOSE}),
        [
            Prefill([0, 1, 2, 3]),
            Complete(4, gets=[BASIC, RW, lost(R1)]),
            Complete(5, gets=[BASIC, RW], note="1줄 리워드는 이미 추첨해서 다시 뽑지 않는다"),
        ],
        nodes=GEN_SKIP + LINES + REW_LOST + NOT_FULL,
    ),
    Scenario(
        "D3", "D. 리워드", "1줄 → 3줄 → 5줄을 차례로 달성",
        "빙고 줄을 하나씩 늘려 가며 1줄·3줄·5줄 리워드를 차례로 받는다.",
        Setup(coupons=_ALL_REWARDS),
        [
            Prefill([0, 1, 2, 3]),
            Complete(4, gets=[BASIC, RW, R1], note="1줄 달성"),
            Prefill([5, 6, 7, 8, 9, 10, 11, 12, 13]),
            Complete(14, gets=[BASIC, RW, R3], note="3줄 달성(가로 3줄)"),
            Prefill([15, 16, 17, 18, 19]),
            Complete(20, gets=[BASIC, RW, R5], note="5줄 달성(가로 4줄 + 세로 1줄). 리워드 3개는 서로 다른 경품"),
        ],
        nodes=GEN_SKIP + LINES + REW_WIN + NOT_FULL,
    ),
    Scenario(
        "D4", "D. 리워드", "리워드가 마지막 1개 남았을 때, 늦게 도달한 사람은 못 받음",
        "1줄 리워드가 1개 남았다. 두 사람이 차례로 첫 줄을 완성한다.",
        Setup(coupons={"r1": {"win": 100, "stock": 1}}),
        [
            Join(who="other"),
            Prefill([0, 1, 2, 3]),
            Prefill([0, 1, 2, 3], who="other"),
            Complete(4, gets=[BASIC, RW, R1], note="먼저 도달한 사람이 마지막 1개를 받는다"),
            Complete(4, who="other", gets=[BASIC, RW, sold_out(R1)], note="다음 사람은 소진이라 못 받는다"),
        ],
        nodes=GEN_SKIP + LINES + REW_WIN + REW_SOLD + NOT_FULL,
    ),
]

E = [
    Scenario(
        "E1", "E. 빙고 완성", "빙고판 25칸을 모두 채움",
        "빙고판을 채워 가다가 24칸에서 한 칸을 남기고, 마지막 칸을 채워 완성한다.",
        Setup(
            line_stamps=_LINE_STAMPS,
            coupons={"general": WIN, "special": WIN, **_ALL_REWARDS},
        ),
        [
            Prefill(list(range(23))),
            Complete(23, gets=[BASIC, RW, GEN], note="24칸. 한 칸 남아서 스페셜 보상은 아직"),
            Complete(
                24,
                gets=[BASIC, RW, GEN, line_stamp(12), SPECIAL],
                note="25칸 완성. 빙고 12줄 스탬프(스페셜 스탬프)와 스페셜 쿠폰",
            ),
        ],
        nodes=GEN_WIN + LINES + REW_NONE + NOT_FULL + FULL_SP_WIN,
    ),
]

SCENARIOS = A + B + C + D + E
