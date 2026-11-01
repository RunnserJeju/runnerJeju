"""시나리오 하나를 실행해 사건마다 "새로 받은 것"을 기대와 비교한다.

결과(ScenarioResult)에는 판정뿐 아니라 사건마다의 빙고판 상태도 담는다 — 리포트의 타임라인이 쓴다.
"""

from dataclasses import dataclass, field

from sqlalchemy.orm import Session

from scenario_model import AdminIssue, Complete, Join, Prefill, Scenario, SetCoupon
from scenario_world import World


# 이번 실행에서 돌린 시나리오의 결과. 끝나면 conftest가 리포트로 만든다.
RESULTS: list = []


@dataclass
class StepResult:
    description: str
    who: str
    expected: list | None  # None이면 비교하지 않는 사건
    actual: list
    ok: bool
    board: dict | None
    note: str = ""
    prep: bool = False  # 완주가 아닌 준비 단계(칸 미리 채우기, 참가 신청, 설정 변경 등)


@dataclass
class ScenarioResult:
    scenario: Scenario
    steps: list = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(step.ok for step in self.steps)


def describe(event) -> str:
    if isinstance(event, Complete):
        extra = []
        if not event.matched:
            extra.append("검증 실패")
        if event.twice:
            extra.append("같은 인증 2번 요청")
        suffix = f" ({', '.join(extra)})" if extra else ""
        return f"{event.course + 1}번 코스 완주{suffix}"
    if isinstance(event, Join):
        return "러닝위크 참가 신청"
    if isinstance(event, Prefill):
        return f"코스 {len(event.cells)}개를 완주해 칸 {len(event.cells)}개를 채움 (그동안 받은 것은 생략)"
    if isinstance(event, SetCoupon):
        changes = [
            text
            for text in (
                None if event.active is None else ("활성화" if event.active else "비활성화"),
                None if event.win is None else f"확률 {event.win}%",
                None if event.stock is None else f"수량 {event.stock}",
            )
            if text
        ]
        return f"{event.key} 쿠폰 설정 변경 ({', '.join(changes)})"
    if isinstance(event, AdminIssue):
        return f"운영자가 {event.key} 쿠폰 {event.count}장 수동 발급"
    raise TypeError(event)


def run_scenario(db: Session, scenario: Scenario) -> ScenarioResult:
    world = World.build(db, scenario.setup)
    result = ScenarioResult(scenario)

    for event in scenario.events:
        who = getattr(event, "who", "me")
        before = world.received(who)

        if isinstance(event, Complete):
            world.complete(event)
        elif isinstance(event, Join):
            world.join(event.who)
        elif isinstance(event, Prefill):
            world.prefill(event.who, event.cells)
        elif isinstance(event, SetCoupon):
            world.set_coupon(event.key, event.active, event.win, event.stock)
        elif isinstance(event, AdminIssue):
            world.admin_issue(event.key, event.count)

        actual = sorted((world.received(who) - before).elements())
        expected = getattr(event, "gets", None)
        expected = None if expected is None else sorted(expected)
        result.steps.append(
            StepResult(
                description=describe(event),
                who=who,
                expected=expected,
                actual=actual,
                ok=expected is None or expected == actual,
                board=world.board(who),
                note=getattr(event, "note", ""),
                prep=not isinstance(event, Complete),
            )
        )
    RESULTS.append(result)
    return result


def failure_message(result: ScenarioResult) -> str:
    lines = [f"[{result.scenario.id}] {result.scenario.name} — {result.scenario.situation}"]
    for number, step in enumerate(result.steps, 1):
        mark = "ok  " if step.ok else "FAIL"
        lines.append(f"  {mark} {number}. {step.description}")
        if not step.ok:
            lines.append(f"         기대: {step.expected}")
            lines.append(f"         실제: {step.actual}")
    return "\n".join(lines)
