"""운영자 지표 API — 지표 이름을 파라미터로 받는 집계 엔드포인트.

registry(무엇을 셀지) · sources(어떻게 셀지) · router(HTTP)로 나뉜다. 새 지표는
registry에 한 줄 등록하면 끝이고, user_log 기반 지표는 LOG_NAMES에 이름을 넣는
것만으로 자동 등록된다. HTTP 라우터는 app.admin.metrics.router.router다.
"""
