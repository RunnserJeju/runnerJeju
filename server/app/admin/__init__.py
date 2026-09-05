"""운영자 전용 API 묶음.

`admin_router`의 하위 라우터는 모두 `/admin` 아래에 놓이고, 라우터 레벨에서
require_admin_session으로 보호된다 — 개별 엔드포인트에 가드를 붙이지 않아도
로그인한 운영자만 접근할 수 있다.

`admin_auth_router`(로그인/로그아웃/세션확인)는 가드 밖에 둔다 — 로그인은 세션이
없어도 닿아야 하기 때문이다. 둘 다 main.py에서 앱에 등록한다.
"""

from fastapi import APIRouter, Depends

from app.admin import courses, geo, missions, notices
from app.admin.auth import require_admin_session
from app.admin.auth import router as admin_auth_router

admin_router = APIRouter(
    prefix="/admin", dependencies=[Depends(require_admin_session)]
)
admin_router.include_router(courses.router)
admin_router.include_router(notices.router)
admin_router.include_router(missions.router)
admin_router.include_router(geo.router)

__all__ = ["admin_router", "admin_auth_router"]
