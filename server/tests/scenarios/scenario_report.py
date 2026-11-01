"""시나리오 실행 결과를 HTML 한 장으로 만든다. 외부 라이브러리 없이 흐름도를 직접 그린다 —
오프라인에서도 열리고, 노드 색칠·경로 강조를 마음대로 다룰 수 있다.

화면: 왼쪽에 흐름도, 오른쪽에 시나리오 목록. 시나리오를 누르면 흐름도에 그 시나리오가 지나는 길이
켜지고 사건별 타임라인(빙고판 변화, 받은 것)이 펼쳐진다. 흐름도의 노드를 누르면 그 노드를 지나는
시나리오만 목록에 남는다. 노드 모서리의 숫자는 그 노드를 지나는 시나리오 수이고, 초록이면 모두
통과, 빨강이면 실패가 있고, 회색 점선(0)이면 어떤 시나리오도 지나지 않는 곳이다.
"""

import html
import shutil
from datetime import datetime
from pathlib import Path

from scenario_flow import EDGES, FRAMES, NODES
from scenario_model import COUPON_KEYS

REPORT_ROOT = Path(__file__).resolve().parents[2] / "test-reports"
KEEP_HISTORY = 10

# ---- 흐름도 그리기 ----
SPINE_X, SPINE_W = 70, 250
LEAF_X, LEAF_W = 400, 220
LANE_X = 26
TOP, ROW_H = 44, 100
VIEW_W = 640
HEIGHT = {"start": 44, "decision": 64, "grant": 56, "end": 46}
# 상자 제목이 들어갈 자리와 상자 아래 여백. 줄 위치는 이만큼씩 아래로 밀린다.
FRAME_TITLE, REGION_TITLE, FRAME_PAD = 34, 30, 14
# 줄 가운데에서 상자 위·아래 끝까지(결과 노드가 위아래로 벌어진 줄까지 감싼다).
BAND_UP, BAND_DOWN = 50, 56


def _title_space(frame) -> int:
    return REGION_TITLE if frame.region else FRAME_TITLE


def _row_y(row: int) -> float:
    """줄 가운데의 y. 앞에서 시작한 상자의 제목 자리와 앞에서 끝난 상자의 여백만큼 밀린다."""
    offset = sum(_title_space(f) for f in FRAMES if f.start <= row)
    offset += sum(FRAME_PAD for f in FRAMES if f.end < row)
    return TOP + row * ROW_H + offset


def _geom(node):
    x, w = (SPINE_X, SPINE_W) if node.col == 0 else (LEAF_X, LEAF_W)
    h = HEIGHT[node.kind] if node.col == 0 else 46
    cy = _row_y(node.row) + node.dy
    return x, w, h, cy


def _frame_svg(frame) -> str:
    # 같은 줄에서 시작하는 상자 중 이 상자와 그 안쪽 상자들의 제목 자리만큼 위로 연다.
    inner = [f for f in FRAMES if f.start == frame.start and (f is frame or not f.region)]
    if not frame.region:
        inner = [frame]
    top = _row_y(frame.start) - BAND_UP - sum(_title_space(f) for f in inner) + 8
    bottom = _row_y(frame.end) + BAND_DOWN + (8 if frame.region else 0)
    x, w = (6, VIEW_W - 12) if frame.region or not _inside_region(frame) else (14, VIEW_W - 28)
    cls = "frame region" if frame.region else "frame"
    return (
        f'<g class="{cls}"><rect x="{x}" y="{top}" width="{w}" height="{bottom - top}" rx="10"/>'
        # 큰 영역의 제목은 오른쪽에 둔다 — 가운데로 지나는 화살표와 겹치지 않게.
        + (
            f'<text class="ftitle" x="{x + w - 12}" y="{top + 20}" text-anchor="end">{_esc(frame.title)}</text></g>'
            if frame.region
            else f'<text class="ftitle" x="{x + 12}" y="{top + 20}">{_esc(frame.title)}</text></g>'
        )
    )


def _inside_region(frame) -> bool:
    return any(r.region and r.start <= frame.start and frame.end <= r.end for r in FRAMES if r is not frame)


def _esc(text) -> str:
    return html.escape(str(text), quote=True)


def _coverage(results):
    """노드별로 그 노드를 지나는 시나리오 id들."""
    visited = {node.id: [] for node in NODES}
    for result in results:
        for node_id in dict.fromkeys(result.scenario.nodes):
            visited[node_id].append(result)
    return visited


def _node_svg(node, visited) -> str:
    x, w, h, cy = _geom(node)
    top = cy - h / 2
    if node.kind == "decision":
        points = [(x, cy), (x + 14, top), (x + w - 14, top), (x + w, cy), (x + w - 14, top + h), (x + 14, top + h)]
        shape = f'<polygon class="shape" points="{" ".join(f"{px},{py}" for px, py in points)}"/>'
    else:
        radius = h / 2 if node.kind == "start" else 8
        shape = f'<rect class="shape" x="{x}" y="{top}" width="{w}" height="{h}" rx="{radius}"/>'

    count = len(node.lines)
    texts = []
    for i, line in enumerate(node.lines):
        ty = cy - (count - 1) * 8 + i * 16 + 4
        cls = "t main" if i == 0 else "t sub"
        if count == 1:
            cls = "t main"
        texts.append(f'<text class="{cls}" x="{x + w / 2}" y="{ty}" text-anchor="middle">{_esc(line)}</text>')

    hits = visited[node.id]
    if not hits:
        state, tip = "none", "이 노드를 지나는 시나리오가 없어요"
    elif all(r.passed for r in hits):
        state, tip = "ok", "지나는 시나리오: " + ", ".join(r.scenario.id for r in hits)
    else:
        state, tip = "fail", "실패 있음 — " + ", ".join(r.scenario.id for r in hits)
    badge = (
        f'<g class="badge b-{state}"><circle cx="{x + w - 4}" cy="{top + 3}" r="11"/>'
        f'<text x="{x + w - 4}" y="{top + 7}" text-anchor="middle">{len(hits)}</text></g>'
    )
    return (
        f'<g class="node k-{node.kind}" data-node="{node.id}" data-y="{cy}" tabindex="0">'
        f"<title>{_esc(tip)}</title>{shape}{''.join(texts)}{badge}</g>"
    )


def _edge_svg(edge) -> str:
    nodes = {n.id: n for n in NODES}
    sx, sw, sh, scy = _geom(nodes[edge.src])
    dx, dw, dh, dcy = _geom(nodes[edge.dst])
    label = ""
    if edge.kind == "down":
        cx = sx + sw / 2
        y1, y2 = scy + sh / 2, dcy - dh / 2
        d = f"M{cx},{y1} L{cx},{y2}"
        if edge.label:
            label = (cx + 8, (y1 + y2) / 2 + 4, "start")
    elif edge.kind == "right":
        x1 = sx + sw
        mid = x1 + 28
        d = f"M{x1},{scy} L{dx},{dcy}" if dcy == scy else f"M{x1},{scy} L{mid},{scy} L{mid},{dcy} L{dx},{dcy}"
        label = ((x1 + 8, scy - 6, "start") if dcy == scy else (mid + 6, dcy - 6, "start"))
    else:  # bypass: 왼쪽 길로 돌아 아래 노드의 왼쪽으로 들어간다
        d = f"M{sx},{scy} L{LANE_X},{scy} L{LANE_X},{dcy} L{dx},{dcy}"
        label = (sx - 6, scy - 6, "end")
    text = ""
    if edge.label and label:
        text = f'<text class="elabel" x="{label[0]}" y="{label[1]}" text-anchor="{label[2]}">{_esc(edge.label)}</text>'
    unless = " ".join(edge.unless)
    return (
        f'<g class="edge" data-src="{edge.src}" data-dst="{edge.dst}" data-unless="{unless}">'
        f'<path d="{d}" marker-end="url(#arrow)"/>{text}</g>'
    )


def flow_svg(results) -> str:
    visited = _coverage(results)
    height = _row_y(max(n.row for n in NODES)) + BAND_DOWN + 8 + 20
    return (
        f'<svg id="flow" viewBox="0 0 {VIEW_W} {height}" role="img" '
        f'aria-label="러닝위크 지급 흐름도">'
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" '
        'markerWidth="9" markerHeight="9" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z"/></marker></defs>'
        + "".join(_frame_svg(f) for f in FRAMES)
        + "".join(_edge_svg(e) for e in EDGES)
        + "".join(_node_svg(n, visited) for n in NODES)
        + "</svg>"
    )


# ---- 시나리오 카드 ----
_WEEK = {"open": "공개 중", "inactive": "비활성화", "before": "기간 전", "after": "기간 후"}
_COUPON_NAME = {"general": "일반 쿠폰", "special": "스페셜 쿠폰", "r1": "1줄 리워드", "r3": "3줄 리워드", "r5": "5줄 리워드"}


def _setup_chips(setup) -> list:
    chips = [
        f"회차 {_WEEK[setup.week]}",
        "참가 신청함" if setup.participates else "참가 신청 안 함",
        "빙고판 배치 있음" if setup.bingo else "빙고판 배치 없음",
    ]
    if setup.line_stamps:
        chips.append("줄 스탬프 " + "·".join(str(n) for n in setup.line_stamps) + "줄")
    on = []
    for key in COUPON_KEYS:
        cfg = setup.coupons.get(key)
        if cfg is None:
            continue
        win = cfg.get("win", 100)
        result = {100: "당첨으로 고정", 0: "낙첨으로 고정"}.get(win, f"확률 {win}%")
        text = f"{_COUPON_NAME[key]} (추첨 {result})"
        if cfg.get("stock") is not None:
            text += f" · 남은 수량 {cfg['stock']}"
        on.append(text)
    chips.append("활성화된 쿠폰: " + (", ".join(on) if on else "없음"))
    return chips


def _rank(label: str) -> tuple:
    """받은 것 칩의 표시 순서: 스탬프 → 쿠폰 → 낙첨 → 소진."""
    if label.startswith("낙첨:"):
        return (3, label)
    if label.startswith("소진:"):
        return (4, label)
    if "스탬프" in label:
        return (0, label)
    return (1 if "리워드" not in label else 2, label)


def _chips(labels) -> str:
    return "".join(_chip(label) for label in sorted(labels, key=_rank))


def _chip(label: str) -> str:
    kind = "lost" if label.startswith("낙첨:") else "sold" if label.startswith("소진:") else "got"
    return f'<span class="chip {kind}">{_esc(label)}</span>'


def _board_svg(board) -> str:
    if board is None:
        return '<span class="noboard">빙고판 없음</span>'
    cells = "".join(f'<i class="{"on" if filled else ""}"></i>' for filled in board["cells"])
    return f'<div class="board" title="완성된 줄 {board["lines"]}개"><div class="grid">{cells}</div><span>{board["lines"]}줄</span></div>'


def _card(result) -> str:
    sc = result.scenario
    steps = []
    for number, step in enumerate(result.steps, 1):
        got = _chips(step.actual) or '<span class="none">받은 것 없음</span>'
        expect = ""
        if not step.ok:
            expect = (
                '<div class="expect">기대: '
                + (_chips(step.expected) or "받은 것 없음")
                + "</div>"
            )
        note = f'<div class="note">{_esc(step.note)}</div>' if step.note else ""
        owner = f' <span class="who">{_esc(step.who)}</span>' if step.who != "me" else ""
        if step.prep:
            got = ""
        steps.append(
            f'<li class="step {"ok" if step.ok else "fail"}{" prep" if step.prep else ""}">'
            f'<div class="sn">{number}</div>'
            f'<div class="sb"><div class="sd">{_esc(step.description)}{owner}</div>'
            f'{f"<div class=got>{got}</div>" if got else ""}{expect}{note}</div>'
            f'{_board_svg(step.board) if step.board is not None or step.expected is not None else ""}'
            "</li>"
        )
    chips = "".join(f'<span class="chip setup">{_esc(c)}</span>' for c in _setup_chips(sc.setup))
    state = "ok" if result.passed else "fail"
    return (
        f'<article class="sc {state}" data-id="{sc.id}" data-nodes="{" ".join(dict.fromkeys(sc.nodes))}">'
        f'<button type="button" class="sh"><span class="sid">{sc.id}</span>'
        f'<span class="sname">{_esc(sc.name)}</span>'
        f'<span class="mark">{"통과" if result.passed else "실패"}</span></button>'
        f'<div class="sbody"><p class="sit">{_esc(sc.situation)}</p>'
        f'<div class="setup">{chips}</div><ol class="steps">{"".join(steps)}</ol></div></article>'
    )


def _groups(results) -> str:
    out, current = [], None
    for result in results:
        if result.scenario.group != current:
            if current is not None:
                out.append("</section>")
            current = result.scenario.group
            members = [r for r in results if r.scenario.group == current]
            passed = sum(r.passed for r in members)
            out.append(f'<section class="grp"><h3>{_esc(current)} <small>{passed}/{len(members)}</small></h3>')
        out.append(_card(result))
    out.append("</section>")
    return "".join(out)


# ---- 페이지 ----
_CSS = """
:root{--frame-bg:#f1f4f1;--bg:#f5f6f4;--panel:#fff;--ink:#1d2421;--muted:#5f6b65;--line:#d6dbd7;--accent:#1f6f54;--edge:#8a958f;
--start-bg:#dbe7f5;--start-line:#3b6aa0;--dec-bg:#fff4d6;--dec-line:#b7791f;--grant-bg:#cdeed9;--grant-line:#2e7d32;
--end-bg:#e3e6e4;--end-line:#7b8580;--ok:#2e7d32;--fail:#c62828;--none:#8a958f;--chip-bg:#eef1ee;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--frame-bg:#212926;--bg:#141918;--panel:#1b2220;--ink:#e8ece9;--muted:#9aa59f;
--line:#2f3834;--accent:#6fcfa6;--edge:#6d7873;--start-bg:#1f3347;--start-line:#6b9bd1;--dec-bg:#3a3118;--dec-line:#d9a441;
--grant-bg:#1c3d2a;--grant-line:#5bb36a;--end-bg:#2a302d;--end-line:#8a958f;--ok:#5bb36a;--fail:#ef6f6f;--none:#8a958f;--chip-bg:#262e2b;color-scheme:dark}}
:root[data-theme="dark"]{--frame-bg:#212926;--bg:#141918;--panel:#1b2220;--ink:#e8ece9;--muted:#9aa59f;--line:#2f3834;--accent:#6fcfa6;--edge:#6d7873;
--start-bg:#1f3347;--start-line:#6b9bd1;--dec-bg:#3a3118;--dec-line:#d9a441;--grant-bg:#1c3d2a;--grant-line:#5bb36a;
--end-bg:#2a302d;--end-line:#8a958f;--ok:#5bb36a;--fail:#ef6f6f;--none:#8a958f;--chip-bg:#262e2b;color-scheme:dark}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--ink);margin:0;font:14px/1.6 "Apple SD Gothic Neo","Malgun Gothic","Noto Sans KR",system-ui,sans-serif;
padding-block:24px 56px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
header.top{max-width:1240px;margin:0 auto 18px}
h1{font-size:24px;line-height:1.3;margin:0 0 6px}
.sum{display:flex;flex-wrap:wrap;gap:8px 20px;color:var(--muted)}
.sum b{color:var(--ink)}
.sum .bad{color:var(--fail);font-weight:700}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:10px;font-size:12.5px;color:var(--muted)}
.legend span{display:inline-flex;align-items:center;gap:6px}
.sw{width:14px;height:14px;border-radius:3px;border:1.5px solid;display:inline-block}
.sw.dec{background:var(--dec-bg);border-color:var(--dec-line)}.sw.grant{background:var(--grant-bg);border-color:var(--grant-line)}
.sw.end{background:var(--end-bg);border-color:var(--end-line)}
.dot{width:14px;height:14px;border-radius:50%;display:inline-block;border:2px solid}
.dot.ok{border-color:var(--ok)}.dot.fail{border-color:var(--fail)}.dot.none{border-color:var(--none);border-style:dashed}
main{max-width:1240px;margin:0 auto;display:grid;grid-template-columns:minmax(0,640px) minmax(0,1fr);gap:20px;align-items:start}
.flowwrap{position:sticky;top:12px;max-height:calc(100vh - 24px);overflow:auto;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px}
#flow{width:100%;height:auto;display:block}
#flow text{font-family:inherit;fill:var(--ink)}
#flow .t.main{font-size:13px;font-weight:600}#flow .t.sub{font-size:11.5px;fill:var(--muted)}
#flow .shape{stroke-width:1.5}
#flow .frame rect{fill:var(--frame-bg);stroke:var(--line);stroke-width:1.2}
#flow .frame.region rect{fill:none;stroke:var(--accent);stroke-width:1.5;stroke-dasharray:7 5}
#flow .ftitle{font-size:12.5px;font-weight:700;fill:var(--muted)}
#flow .frame.region .ftitle{fill:var(--accent)}
#flow .k-start .shape{fill:var(--start-bg);stroke:var(--start-line)}
#flow .k-decision .shape{fill:var(--dec-bg);stroke:var(--dec-line)}
#flow .k-grant .shape{fill:var(--grant-bg);stroke:var(--grant-line)}
#flow .k-end .shape{fill:var(--end-bg);stroke:var(--end-line)}
#flow .edge path{fill:none;stroke:var(--edge);stroke-width:1.6}
#flow marker path{fill:var(--edge);stroke:none}
#flow .elabel{font-size:11px;fill:var(--muted)}
#flow .node{cursor:pointer;outline:none}
#flow .node:focus-visible .shape{stroke:var(--accent);stroke-width:3}
#flow .badge circle{stroke-width:2;fill:var(--panel)}
#flow .badge text{font-size:11px;font-weight:700;text-anchor:middle}
#flow .b-ok circle{stroke:var(--ok)}.b-ok text{fill:var(--ok)}
#flow .b-fail circle{stroke:var(--fail);fill:var(--fail)}#flow .b-fail text{fill:#fff}
#flow .b-none circle{stroke:var(--none);stroke-dasharray:3 2}#flow .b-none text{fill:var(--none)}
#flow.sel .node,#flow.sel .edge{opacity:.28}
#flow.sel .node.on,#flow.sel .edge.on{opacity:1}
#flow .node.on .shape{stroke:var(--accent);stroke-width:3.5}
#flow .edge.on path{stroke:var(--accent);stroke-width:3.2}
#flow .node.picked .shape{stroke:var(--accent);stroke-width:3.5;stroke-dasharray:6 3}
.listhead{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:center;margin-bottom:8px}
.listhead .hint{color:var(--muted);font-size:12.5px;flex:1 1 220px}
.pill{border:1px solid var(--line);background:var(--panel);color:var(--ink);border-radius:999px;padding:3px 12px;cursor:pointer;font:inherit;font-size:12.5px}
.pill[hidden]{display:none}
.grp h3{font-size:15px;margin:18px 0 8px}.grp h3 small{color:var(--muted);font-weight:400;margin-left:6px}
.sc{background:var(--panel);border:1px solid var(--line);border-radius:10px;margin-bottom:8px;overflow:hidden}
.sc.fail{border-color:var(--fail)}
.sc.hide{display:none}
.sc{scroll-margin-top:12px}
.sh{all:unset;box-sizing:border-box;display:flex;align-items:center;gap:10px;width:100%;padding:10px 14px;cursor:pointer}
.sh:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
.sid{font-weight:700;min-width:34px;color:var(--accent)}.sname{flex:1;min-width:0}
.mark{font-size:12px;font-weight:700;padding:1px 9px;border-radius:999px;border:1.5px solid}
.sc.ok .mark{color:var(--ok);border-color:var(--ok)}.sc.fail .mark{color:#fff;background:var(--fail);border-color:var(--fail)}
.sc.open{border-color:var(--accent)}
.sbody{display:none;padding:0 14px 14px;border-top:1px solid var(--line)}
.sc.open .sbody{display:block}
.sit{margin:10px 0 8px}
.setup{display:flex;flex-wrap:wrap;gap:5px;margin-bottom:10px}
.chip{display:inline-block;padding:1px 9px;border-radius:999px;font-size:12.5px;background:var(--chip-bg);border:1px solid var(--line)}
.chip.setup{color:var(--muted)}
.chip.got{background:var(--grant-bg);border-color:var(--grant-line)}
.chip.lost{background:var(--dec-bg);border-color:var(--dec-line)}
.chip.sold{background:var(--end-bg);border-color:var(--end-line)}
.steps{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:8px}
.step{display:flex;gap:10px;align-items:flex-start;padding:8px 10px;border-radius:8px;background:var(--bg);border:1px solid transparent}
.step.fail{border-color:var(--fail)}
.step.prep{background:none;border:1px dashed var(--line);color:var(--muted)}.step.prep .sd{font-weight:400}
.sn{width:22px;height:22px;border-radius:50%;background:var(--panel);border:1px solid var(--line);text-align:center;font-size:12px;line-height:20px;flex:none}
.sb{flex:1;min-width:0}.sd{font-weight:600}.who{font-weight:400;color:var(--muted);font-size:12px}
.got{display:flex;flex-wrap:wrap;gap:5px;margin-top:4px}.none{color:var(--muted);font-size:12.5px}
.expect{margin-top:6px;color:var(--fail);font-size:12.5px}
.note{margin-top:4px;color:var(--muted);font-size:12.5px}
.board{display:flex;flex-direction:column;align-items:center;gap:2px;flex:none;font-size:11px;color:var(--muted)}
.board .grid{display:grid;grid-template-columns:repeat(5,9px);gap:2px}
.board i{width:9px;height:9px;border-radius:2px;background:var(--panel);border:1px solid var(--line);display:block}
.board i.on{background:var(--accent);border-color:var(--accent)}
.noboard{font-size:11px;color:var(--muted);flex:none}
@media (max-width:980px){main{grid-template-columns:minmax(0,1fr)}.flowwrap{position:static;max-height:70vh}}
@media (prefers-reduced-motion:no-preference){.sc,.sh{transition:border-color .15s}}
"""

_JS = """
(function(){
  var svg=document.getElementById('flow'),wrap=document.querySelector('.flowwrap');
  var cards=[].slice.call(document.querySelectorAll('.sc'));
  var nodeEls=[].slice.call(svg.querySelectorAll('.node'));
  var edgeEls=[].slice.call(svg.querySelectorAll('.edge'));
  var clear=document.getElementById('clear'),filt=document.getElementById('filt');
  var picked=null,selected=null;
  function paint(ids){
    var set={};ids.forEach(function(i){set[i]=1});
    svg.classList.toggle('sel',ids.length>0);
    nodeEls.forEach(function(n){n.classList.toggle('on',!!set[n.dataset.node])});
    edgeEls.forEach(function(e){
      var u=(e.dataset.unless||'').split(' ').filter(Boolean);
      var on=set[e.dataset.src]&&set[e.dataset.dst]&&!u.some(function(x){return set[x]});
      e.classList.toggle('on',!!on);
    });
  }
  function select(card){
    cards.forEach(function(c){c.classList.remove('open')});
    selected=card;
    if(!card){paint([]);syncClear();return}
    card.classList.add('open');
    card.scrollIntoView({behavior:'smooth',block:'start'});
    var ids=card.dataset.nodes.split(' ');paint(ids);
    var ys=ids.map(function(i){var n=svg.querySelector('[data-node="'+i+'"]');return n?+n.dataset.y:0});
    var scale=svg.clientWidth/640;
    wrap.scrollTo({top:Math.max(0,Math.min.apply(null,ys)*scale-wrap.clientHeight/4),behavior:'smooth'});
    syncClear();
  }
  function pick(id){
    picked=id;
    nodeEls.forEach(function(n){n.classList.toggle('picked',n.dataset.node===id)});
    cards.forEach(function(c){c.classList.toggle('hide',!!id&&c.dataset.nodes.split(' ').indexOf(id)<0)});
    document.querySelectorAll('.grp').forEach(function(g){g.hidden=!g.querySelector('.sc:not(.hide)')});
    var n=id&&svg.querySelector('[data-node="'+id+'"]');
    filt.textContent=n?'필터: '+[].map.call(n.querySelectorAll('.t'),function(t){return t.textContent}).join(' ')+' ✕':'';
    filt.hidden=!n;
    if(selected&&selected.classList.contains('hide'))select(null);
    syncClear();
  }
  function syncClear(){clear.hidden=!selected}
  cards.forEach(function(c){c.querySelector('.sh').addEventListener('click',function(){select(c===selected?null:c)})});
  nodeEls.forEach(function(n){
    n.addEventListener('click',function(){pick(picked===n.dataset.node?null:n.dataset.node)});
    n.addEventListener('keydown',function(e){if(e.key==='Enter'||e.key===' '){e.preventDefault();n.dispatchEvent(new Event('click'))}});
  });
  clear.addEventListener('click',function(){select(null)});
  filt.addEventListener('click',function(){pick(null)});
  var first=document.querySelector('.sc.fail');if(first)select(first);
})();
"""


def build_html(results, *, fragment: bool = False) -> str:
    """fragment=True면 doctype/html/head/body 없이 내용만(아티팩트로 올릴 때)."""
    total = len(results)
    passed = sum(r.passed for r in results)
    visited = _coverage(results)
    covered = sum(1 for hits in visited.values() if hits)
    gray = len(NODES) - covered
    failed = total - passed
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    summary = (
        f'<span>시나리오 <b>{passed}/{total}</b> 통과</span>'
        + (f'<span class="bad">실패 {failed}개</span>' if failed else "")
        + f'<span>흐름도 <b>{covered}/{len(NODES)}</b> 노드를 시나리오가 지나감'
        + (f' · <b>{gray}개는 아무 시나리오도 안 지남</b>' if gray else "")
        + f"</span><span>{stamp} 실행</span>"
    )
    legend = (
        '<span><i class="sw dec"></i>조건</span><span><i class="sw grant"></i>받는 것</span>'
        '<span><i class="sw end"></i>끝·미지급</span>'
        '<span><i class="dot ok"></i>노드 모서리 숫자 = 지나는 시나리오 수(모두 통과)</span>'
        '<span><i class="dot fail"></i>실패 있음</span><span><i class="dot none"></i>지나는 시나리오 없음</span>'
    )
    body = (
        '<header class="top"><h1>러닝위크 지급 시나리오</h1>'
        f'<div class="sum">{summary}</div><div class="legend">{legend}</div></header>'
        f'<main><div class="flowwrap">{flow_svg(results)}</div>'
        '<div><div class="listhead"><span class="hint">시나리오를 누르면 흐름도에 지나는 길이 켜지고, '
        "흐름도의 노드를 누르면 그 노드를 지나는 시나리오만 남아요.</span>"
        '<button type="button" class="pill" id="clear" hidden>선택 해제</button>'
        '<button type="button" class="pill" id="filt" hidden></button></div>'
        f"{_groups(results)}</div></main>"
        f"<script>{_JS}</script>"
    )
    title = "<title>러닝위크 지급 시나리오</title>"
    if fragment:
        return f'{title}\n<meta name="claude:viewport-fit-sides" content="cover">\n<style>{_CSS}</style>\n{body}'
    return (
        '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"{title}<style>{_CSS}</style></head><body>{body}</body></html>"
    )


def build_summary(results) -> str:
    """GitHub Actions 실행 페이지에 띄울 짧은 요약(Markdown). 자세한 건 HTML 리포트를 본다."""
    total = len(results)
    passed = sum(r.passed for r in results)
    lines = [
        "## 러닝위크 지급 시나리오",
        "",
        f"**{passed}/{total} 통과**" + ("" if passed == total else f" · **실패 {total - passed}개**"),
        "",
        "| 그룹 | 통과 |",
        "|---|---|",
    ]
    groups = list(dict.fromkeys(r.scenario.group for r in results))
    for group in groups:
        members = [r for r in results if r.scenario.group == group]
        lines.append(f"| {group} | {sum(r.passed for r in members)}/{len(members)} |")
    failed = [r for r in results if not r.passed]
    if failed:
        lines += ["", "### 실패한 시나리오", ""]
        for result in failed:
            lines.append(f"- **{result.scenario.id} {result.scenario.name}**")
            for number, step in enumerate(result.steps, 1):
                if not step.ok:
                    expected = ", ".join(step.expected) or "받은 것 없음"
                    actual = ", ".join(step.actual) or "받은 것 없음"
                    lines.append(f"  - {number}. {step.description} — 기대: {expected} / 실제: {actual}")
    lines += ["", "흐름도와 시나리오별 타임라인은 이 실행의 **Artifacts → scenario-report**를 내려받아 HTML을 열어 보세요."]
    return "\n".join(lines) + "\n"


def write_report(results) -> Path:
    """test-reports/latest/ 에 최신 결과를, 시각별 폴더에 보관본을 쓴다. 오래된 보관본은 지운다.
    latest/summary.md는 CI가 실행 페이지 요약으로 쓴다."""
    page = build_html(results)
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    for folder in (REPORT_ROOT / "latest", REPORT_ROOT / stamp):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "scenario-report.html").write_text(page, encoding="utf-8")
    (REPORT_ROOT / "latest" / "summary.md").write_text(build_summary(results), encoding="utf-8")
    history = sorted(p for p in REPORT_ROOT.iterdir() if p.is_dir() and p.name != "latest")
    for old in history[:-KEEP_HISTORY]:
        shutil.rmtree(old, ignore_errors=True)
    return REPORT_ROOT / "latest" / "scenario-report.html"
