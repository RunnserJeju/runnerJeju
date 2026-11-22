"""알림 종류. 자동 발송을 붙일 때 여기에 한 줄 추가한다(LOG_NAMES와 같은 방식).

운영툴이 이 목록을 그대로 보여준다. 광고성 알림은 아직 없다 — 넣으려면 수신 동의부터.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class NotificationType:
    key: str
    label: str
    # 운영자가 직접 보내는 종류면 False, 시스템이 보내면 True.
    automatic: bool


OPERATOR_NOTICE = "operator_notice"

TYPES: dict[str, NotificationType] = {
    t.key: t
    for t in (
        NotificationType(OPERATOR_NOTICE, "운영자 발송", automatic=False),
    )
}


# 알림을 눌렀을 때 열 수 있는 앱 화면. link_url에는 `app:<키>`로 저장한다.
# 앱(알림 탭 처리)과 같은 키를 써야 한다 — 추가하면 앱도 같이 고친다.
HOME_SCREEN = "home"

SCREENS: dict[str, str] = {
    HOME_SCREEN: "홈",
    "notifications": "알림함",
    "community": "커뮤니티",
    "running-week": "러닝위크",
    "running": "러닝(코스 지도)",
    "stamps": "스탬프",
    "coupons": "쿠폰함",
    "profile": "마이페이지",
}

APP_LINK_PREFIX = "app:"
