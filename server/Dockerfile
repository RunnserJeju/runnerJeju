# uv가 미리 들어있는 공식 이미지. 로컬 개발 환경(3.13)과 파이썬 버전을 맞춘다.
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

# 가상환경을 /app 밖에 둔다. 개발 시 compose가 소스를 /app에 바인드 마운트하는데,
# venv가 /app 안에 있으면 마운트에 가려져 사라진다.
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 의존성만 먼저 설치한다. 소스만 바뀐 재빌드에서 이 레이어가 캐시된다.
#
# dev 그룹(pytest)까지 넣는 이유는 지금 이 이미지가 개발용 하나뿐이고 테스트도
# 컨테이너 안에서 돌리기 때문이다. 운영 이미지를 따로 만들 때 --no-dev를 붙인다.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

COPY . .

# 엔트리포인트는 /app 밖에 둔다. 바인드 마운트가 /app을 통째로 덮어써도
# 살아남아야 하고, 호스트(Windows) 파일 권한에 영향받지 않아야 한다.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
