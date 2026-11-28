"""앱 원격 설정 — GET /app-settings. 로그인 전에도 받는다(지도는 로그인 화면 뒤에서도 뜬다).

값은 app_settings 테이블에서 바꾼다. 앱은 받은 값을 기기에 두고 다음에 만드는 화면부터 쓴다.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import AppSetting

router = APIRouter(tags=["app-settings"])

# 앱에 내려가는 키와 기본값. 여기 없는 키는 DB에 있어도 내려가지 않는다.
DEFAULTS: dict[str, object] = {
    # 안드로이드 카카오맵을 가상 디스플레이 대신 하이브리드 방식(HC)으로 띄운다.
    "android_map_hybrid_composition": True,
}


@router.get("/app-settings")
def get_app_settings(db: Session = Depends(get_db)) -> dict[str, object]:
    stored = {
        row.key: row.value
        for row in db.execute(select(AppSetting).where(AppSetting.key.in_(DEFAULTS))).scalars()
    }
    # 타입이 기본값과 다르면(잘못 넣은 값) 기본값을 쓴다.
    return {
        key: stored[key] if type(stored.get(key)) is type(default) else default
        for key, default in DEFAULTS.items()
    }
