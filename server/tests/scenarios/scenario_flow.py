"""러닝위크 지급 흐름도의 정의. 리포트가 이 정의대로 그림을 그린다.

흐름도는 사람이 읽는 그림이다. 구현이 바뀌면 여기도 손으로 고친다(시나리오가 어느 노드를 지나는지도
손으로 단다). 시나리오 실행이 이 그림을 자동으로 검증하지는 않는다 — 그림과 구현이 어긋나면
시나리오의 기대 결과가 어긋나는 쪽이 먼저 알려 준다.

세로 한 줄(col 0)이 "계속 진행"하는 길이고, 오른쪽(col 1)은 그 지점에서 나오는 결과·종료다.
러닝위크 보상은 서로 독립된 단계(FRAMES)를 차례로 모두 거친다 — 한 단계에서 받을 것이 없으면
그 단계만 건너뛰고 다음 단계로 간다.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Node:
    id: str
    kind: str  # start | decision | grant | end
    lines: tuple  # 노드 안에 들어갈 글(줄 단위)
    row: int
    col: int = 0
    dy: int = 0  # 같은 줄에 결과가 둘일 때 위(-)·아래(+)로 벌리는 정도


@dataclass(frozen=True)
class Frame:
    """노드 몇 줄을 묶는 상자. region은 단계들을 다시 감싸는 큰 영역이다."""

    title: str
    start: int  # 첫 줄(row)
    end: int  # 마지막 줄(row)
    region: bool = False


@dataclass(frozen=True)
class Edge:
    src: str
    dst: str
    kind: str  # down(아래로) | right(오른쪽 결과로) | bypass(왼쪽으로 돌아 건너뜀)
    label: str = ""
    unless: tuple = ()  # 이 노드들을 지났으면 이 선은 안 탄 것으로 본다(건너뛰는 선 전용)


NODES = (
    Node("S", "start", ("코스 완주 인증 요청",), 0),
    Node("D_dup", "decision", ("같은 인증을", "이미 처리했나?"), 1),
    Node("X_dup", "end", ("이전 결과 그대로 반환", "새로 받는 것 없음"), 1, 1),
    Node("D_match", "decision", ("경로 검증을", "통과했나?"), 2),
    Node("X_nomatch", "end", ("지급 없음",), 2, 1),
    Node("G_basic", "grant", ("기본 코스 스탬프 지급", "참가 여부와 상관없이"), 3),
    Node("D_rw", "decision", ("러닝위크 참가자이고", "기간 중인가?"), 4),
    Node("X_rw", "end", ("여기서 끝", "기본 스탬프만 받음"), 4, 1),
    Node("G_rw", "grant", ("러닝위크 코스 스탬프 지급", "빙고 칸이 채워짐"), 5),
    Node("D_gen", "decision", ("일반 쿠폰이 활성화되어 있고", "이 코스를 아직 안 뽑았나?"), 6),
    Node("D_gen_roll", "decision", ("일반 쿠폰 추첨", "확률 33%"), 7),
    Node("G_gen", "grant", ("일반 쿠폰 1장",), 7, 1, -30),
    Node("X_gen_lost", "end", ("쿠폰 없음", "낙첨 기록만 남음"), 7, 1, 30),
    Node("D_layout", "decision", ("빙고판 배치가 있나?",), 8),
    Node("X_nolayout", "end", ("여기서 끝", "빙고 보상 없음"), 8, 1),
    Node("D_lines", "decision", ("완성된 빙고 줄이 있나?",), 9),
    Node("X_nolines", "end", ("여기서 끝",), 9, 1),
    Node("G_linestamp", "grant", ("빙고 줄 스탬프 지급", "도달한 줄 수 기준"), 10),
    Node("D_rew", "decision", ("추첨할 리워드가 있나?", "활성화 · 새 기준 도달 · 미추첨"), 11),
    Node("D_stock", "decision", ("그 리워드 수량이", "남아 있나?"), 12),
    Node("X_rew_sold", "end", ("미지급", "소진 기록만 남음"), 12, 1),
    Node("D_rew_roll", "decision", ("리워드 추첨 (기준마다 따로)", "1·3줄 33% · 5줄 50%"), 13),
    Node("G_rew", "grant", ("해당 줄 리워드 1개",), 13, 1, -30),
    Node("X_rew_lost", "end", ("미지급", "낙첨 기록만 남음"), 13, 1, 30),
    Node("D_25", "decision", ("빙고 25칸을", "모두 채웠나?"), 14),
    Node("X_not25", "end", ("여기서 끝",), 14, 1),
    Node("D_sp", "decision", ("스페셜 쿠폰이 활성화되어 있고", "아직 안 받았나?"), 15),
    Node("X_sp_off", "end", ("여기서 끝",), 15, 1),
    Node("D_sp_stock", "decision", ("스페셜 쿠폰 수량이", "남아 있나?"), 16),
    Node("G_sp", "grant", ("스페셜 쿠폰 1장",), 16, 1, -30),
    Node("X_sp_sold", "end", ("미지급", "소진 기록만 남음"), 16, 1, 30),
)

EDGES = (
    Edge("S", "D_dup", "down"),
    Edge("D_dup", "X_dup", "right", "예"),
    Edge("D_dup", "D_match", "down", "아니오"),
    Edge("D_match", "X_nomatch", "right", "아니오"),
    Edge("D_match", "G_basic", "down", "예"),
    Edge("G_basic", "D_rw", "down"),
    Edge("D_rw", "X_rw", "right", "아니오"),
    Edge("D_rw", "G_rw", "down", "예"),
    Edge("G_rw", "D_gen", "down", "다음 단계"),
    Edge("D_gen", "D_gen_roll", "down", "예"),
    Edge("D_gen", "D_layout", "bypass", "건너뜀", unless=("D_gen_roll",)),
    Edge("D_gen_roll", "G_gen", "right", "당첨"),
    Edge("D_gen_roll", "X_gen_lost", "right", "낙첨"),
    Edge("D_gen_roll", "D_layout", "down", "다음 단계"),
    Edge("D_layout", "X_nolayout", "right", "아니오"),
    Edge("D_layout", "D_lines", "down", "예"),
    Edge("D_lines", "X_nolines", "right", "아니오"),
    Edge("D_lines", "G_linestamp", "down", "예"),
    Edge("G_linestamp", "D_rew", "down"),
    Edge("D_rew", "D_stock", "down", "예"),
    Edge("D_rew", "D_25", "bypass", "건너뜀", unless=("D_stock",)),
    Edge("D_stock", "X_rew_sold", "right", "아니오"),
    Edge("D_stock", "D_rew_roll", "down", "예"),
    Edge("D_rew_roll", "G_rew", "right", "당첨"),
    Edge("D_rew_roll", "X_rew_lost", "right", "낙첨"),
    Edge("D_rew_roll", "D_25", "down", "다음 단계"),
    Edge("D_25", "X_not25", "right", "아니오"),
    Edge("D_25", "D_sp", "down", "예"),
    Edge("D_sp", "X_sp_off", "right", "아니오"),
    Edge("D_sp", "D_sp_stock", "down", "예"),
    Edge("D_sp_stock", "X_sp_sold", "right", "아니오"),
    Edge("D_sp_stock", "G_sp", "right", "예"),
)

# 위에서부터. 같은 줄에서 시작하는 상자는 바깥 상자를 먼저 적는다.
FRAMES = (
    Frame("모든 사용자 · 인증과 기본 스탬프", 0, 3),
    Frame("러닝위크 참가자 전용 (기간 중) · 아래 단계를 차례로 모두 거친다", 5, 16, region=True),
    Frame("① 러닝위크 스탬프", 5, 5),
    Frame("② 일반 쿠폰", 6, 7),
    Frame("③ 빙고 줄 · 리워드", 8, 13),
    Frame("④ 빙고 완성 · 스페셜 쿠폰", 14, 16),
)

NODE_IDS = {node.id for node in NODES}

# ---- 시나리오가 지나는 길의 조각들. 시나리오는 이걸 이어 붙여 nodes를 만든다 ----

ENTRY = ("S", "D_dup", "D_match", "G_basic", "D_rw")
# 러닝위크 참가자의 완주 뒤, 일반 쿠폰 단계가 어떻게 끝나는지
GEN_SKIP = ENTRY + ("G_rw", "D_gen")  # 비활성화되어 있거나 이미 추첨해서 건너뜀
GEN_WIN = ENTRY + ("G_rw", "D_gen", "D_gen_roll", "G_gen")
GEN_LOST = ENTRY + ("G_rw", "D_gen", "D_gen_roll", "X_gen_lost")
# 빙고 단계
NO_LINES = ("D_layout", "D_lines", "X_nolines")
LINES = ("D_layout", "D_lines", "G_linestamp")
REW_NONE = ("D_rew",)
REW_WIN = ("D_rew", "D_stock", "D_rew_roll", "G_rew")
REW_LOST = ("D_rew", "D_stock", "D_rew_roll", "X_rew_lost")
REW_SOLD = ("D_rew", "D_stock", "X_rew_sold")
NOT_FULL = ("D_25", "X_not25")
FULL_SP_OFF = ("D_25", "D_sp", "X_sp_off")
FULL_SP_WIN = ("D_25", "D_sp", "D_sp_stock", "G_sp")
FULL_SP_SOLD = ("D_25", "D_sp", "D_sp_stock", "X_sp_sold")
