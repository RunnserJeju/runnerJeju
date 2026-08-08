"""서버-클라이언트 커버리지 패리티 픽스처의 서버 쪽 검증.

fixtures/coverage_parity.json은 서버 coverage_ratio로 계산한 기대값을 담고 있고,
Flutter 쪽 test/course_coverage_parity_test.dart가 **같은 파일**을 읽어 Dart 구현이
같은 값을 내는지 확인한다. 두 구현은 의도적으로 중복이라(클라는 실시간 증분 계산)
이 픽스처가 둘을 묶는 끈이다.

이 테스트가 깨졌다면 서버 로직이 바뀐 것이다. 그 변경이 의도라면 픽스처를
재생성하고(생성 방법은 아래 docstring), 클라 쪽 테스트도 함께 돌려야 한다.
"""

import json
from pathlib import Path

import pytest

from app import verification

FIXTURE = Path(__file__).parent / "fixtures" / "coverage_parity.json"


@pytest.fixture(scope="module")
def fixture() -> dict:
    return json.loads(FIXTURE.read_text())


def test_fixture_cases_match_current_implementation(fixture):
    """픽스처의 기대값이 현재 서버 구현과 일치하는지(픽스처가 낡지 않았는지)."""
    course = [tuple(p) for p in fixture["course"]]

    for case in fixture["cases"]:
        run = [tuple(p) for p in case["run"]]
        actual = verification.coverage_ratio(
            course, run, tolerance=fixture["tolerance_meters"]
        )
        assert actual == pytest.approx(case["expected_ratio"], abs=1e-9), case["name"]


def test_fixture_uses_current_tolerance(fixture):
    """상수를 바꾸면 픽스처도 재생성해야 한다는 것을 알려주는 가드."""
    assert fixture["tolerance_meters"] == verification.DEFAULT_TOLERANCE_METERS
