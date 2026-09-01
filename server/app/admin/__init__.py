"""운영자 전용 API 묶음.

모든 하위 라우터는 `/admin` 아래에 놓이고, 라우터 레벨에서 require_admin_key로
보호된다 — 개별 엔드포인트에 가드를 붙이지 않아도 관리자만 접근할 수 있다.
운영 기능을 별도 웹으로 빼기 위한 경계다(docs/admin-web.md).
"""

from fastapi import APIRouter, Depends

from app.admin import banners, courses, geo, notices
from app.deps import require_admin_key

admin_router = APIRouter(prefix="/admin", dependencies=[Depends(require_admin_key)])
admin_router.include_router(courses.router)
admin_router.include_router(banners.router)
admin_router.include_router(notices.router)
admin_router.include_router(geo.router)
