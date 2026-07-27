#!/bin/sh
# 서버를 띄우기 전에 반드시 스키마를 최신으로 올린다.
#
# 마이그레이션을 사람이 기억해서 실행하는 구조면 언젠가 빠뜨리게 되고, 그때
# 모델과 DB가 어긋난 채로 서버가 뜬다. 그래서 기동 경로 안에 넣었다.
set -e

echo "▶ alembic upgrade head"
alembic upgrade head

echo "▶ $*"
exec "$@"
