"""시나리오 테스트. 시나리오 목록은 scenarios_*.py에 데이터로 있고, 여기서는 하나씩 돌려 판정한다.

실행: `uv run pytest -m scenario` (Docker가 켜져 있어야 한다. DB는 알아서 띄우고 지운다)
"""

import pytest
import scenarios_ops
import scenarios_user

from scenario_runner import failure_message, run_scenario

# 사용자 시나리오를 먼저, 운영 시나리오를 맨 아래에 둔다(리포트 순서도 같다).
SCENARIOS = scenarios_user.SCENARIOS + scenarios_ops.SCENARIOS


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s.id)
def test_scenario(db, scenario):
    result = run_scenario(db, scenario)
    assert result.passed, "\n" + failure_message(result)


def test_scenario_ids_are_unique_and_nodes_exist():
    """시나리오 id가 겹치지 않고, 시나리오가 가리키는 노드가 흐름도에 실제로 있어야 한다."""
    from scenario_flow import NODE_IDS

    ids = [s.id for s in SCENARIOS]
    assert len(ids) == len(set(ids)), "시나리오 id가 겹쳐요"
    unknown = {(s.id, n) for s in SCENARIOS for n in s.nodes if n not in NODE_IDS}
    assert not unknown, f"흐름도에 없는 노드: {sorted(unknown)}"
