#!/usr/bin/env bash
#
# 백엔드 개발 환경 조작 스크립트. (macOS / Linux)
# 윈도우는 scripts/local_docker_start.ps1 을 쓴다.
#
# DB와 API를 도커로 함께 띄운다. up/rebuild가 컨테이너를 올리기 전에
# 마이그레이션을 먼저 실행하므로 따로 챙길 필요는 없다.
#
# 엔트리포인트가 아니라 여기서 도는 이유는 운영과 조건을 맞추기 위해서다 —
# 운영(Cloud Run)은 마이그레이션을 배포 파이프라인의 별도 스텝으로 뺐다
# (cloudbuild.yaml, docs/cicd.md). 기동 경로에 남겨두면 실패했을 때
# 컨테이너가 재시작만 반복한다.
#
# 사용법:
#   ./scripts/local_docker_start.sh up          # DB + API 기동 (백그라운드)
#   ./scripts/local_docker_start.sh logs        # 로그 따라가기
#   ./scripts/local_docker_start.sh migrate     # 스키마를 head까지 올리기
#   ./scripts/local_docker_start.sh revision "add course tags"
#   ./scripts/local_docker_start.sh seed        # courses/ 의 GPX를 API로 업로드
#   ./scripts/local_docker_start.sh test
#   ./scripts/local_docker_start.sh down

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="$REPO_ROOT/infra/docker-compose.yml"

COMMAND="${1:-up}"
[ $# -gt 0 ] && shift

compose() {
  docker compose -f "$COMPOSE" "$@"
}

# 컨테이너 안에서 일회성 명령을 돌린다. api가 떠 있으면 exec, 아니면 run.
api() {
  if compose ps --status running --services 2>/dev/null | grep -qx 'api'; then
    compose exec api "$@"
  else
    # api가 안 떠 있을 때(그리고 스키마가 어긋나 못 뜰 때)도 돌아야 하므로
    # 일회용 컨테이너를 쓴다.
    compose run --rm --entrypoint= api "$@"
  fi
}

# 이미지를 만들고, 스키마를 head까지 올린 뒤, 컨테이너를 띄운다.
# 순서가 중요하다 — 스키마가 어긋나면 app/schema_guard.py가 기동을 거부한다.
start_stack() {
  compose build
  api alembic upgrade head
  compose up -d "$@"

  echo
  printf '\033[32m  API   http://localhost:8000\033[0m\n'
  printf '\033[32m  docs  http://localhost:8000/docs\033[0m\n'
  printf '\033[90m  로그  ./scripts/local_docker_start.sh logs\033[0m\n'
}

case "$COMMAND" in
  up)      start_stack ;;
  down)    compose down ;;
  restart) compose restart api ;;
  rebuild) start_stack --force-recreate ;;
  logs)    compose logs -f --tail 100 ;;
  status)  compose ps ;;

  migrate) api alembic upgrade head ;;

  revision)
    if [ $# -eq 0 ]; then
      echo '메시지가 필요해요. 예: ./scripts/local_docker_start.sh revision "add course tags"' >&2
      exit 1
    fi
    api alembic revision --autogenerate -m "$@"
    printf '\033[33m생성된 마이그레이션을 반드시 눈으로 확인하세요. autogenerate는 완벽하지 않습니다.\033[0m\n'
    ;;

  psql)  compose exec db psql -U runner -d runner_jeju ;;
  shell) compose exec api bash ;;
  test)  api pytest -q ;;

  seed)  api python -m tools.push_courses "$@" ;;

  *)
    echo "알 수 없는 명령: $COMMAND" >&2
    echo "사용 가능: up down restart rebuild logs migrate revision psql shell test seed status" >&2
    exit 1
    ;;
esac
