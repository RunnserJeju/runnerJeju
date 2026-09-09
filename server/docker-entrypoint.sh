#!/bin/sh
# 앱 기동 경로에서는 스키마를 건드리지 않는다.
#
# 예전엔 여기서 `alembic upgrade head`를 돌렸다. 로컬(인스턴스 1개)에선 편했지만
# Cloud Run에선 물린다 — 마이그레이션이 실패하면 컨테이너가 아예 못 뜨고 재시작만
# 반복해서 정상 인스턴스가 하나도 남지 않는다. 앱을 이전 리비전으로 롤백해도
# DB 스키마는 따라 돌아오지 않는다.
#
# 그래서 "바깥에서 미리 마이그레이트 → 부팅 때는 검증만"으로 나눴다.
#   운영: cloudbuild.yaml의 migrate 스텝(Cloud Run Job)이 배포 직전에 한 번
#   로컬: scripts/local_docker_start.ps1 up 이 컨테이너를 띄우기 전에 실행
#
# 빠뜨렸을 때의 안전망은 app/schema_guard.py다 — alembic_version을 읽어 비교만
# 하고(DB를 바꾸지 않음) 어긋나면 기동을 거부한다.
set -e

echo "▶ $*"
exec "$@"
