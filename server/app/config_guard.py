"""위험한 기본값으로 서버가 뜨는 걸 막고, 어느 DB에 붙었는지 알린다.

개발과 운영이 같은 코드·같은 이미지를 쓰고 환경변수로만 갈린다. 그래서 값을
빠뜨리면 개발용 기본값이 그대로 운영에 실린다. `DATABASE_URL`(연결 거부)이나
`SUPABASE_API_SECRET_KEY`(업로드 에러)는 빠뜨리면 바로 티가 나는데,
`JWT_SECRET_KEY`만 조용히 뜬다 — 그 상태면 누구나 관리자 토큰을 위조할 수 있다.

`schema_guard`와 같은 태도로, 어긋난 채 뜨느니 기동을 거부한다.
"""

import os

from sqlalchemy.engine import Engine

from app.security import INSECURE_DEFAULT_SECRET


class InsecureConfigError(RuntimeError):
    """운영에 나가면 안 되는 설정으로 기동하려 할 때."""


def verify() -> None:
    """JWT 서명 키가 실제 비밀값인지 확인한다."""
    secret = os.environ.get("JWT_SECRET_KEY", "")

    if not secret or secret == INSECURE_DEFAULT_SECRET:
        state = "설정되지 않았어요" if not secret else "개발용 기본값 그대로예요"
        raise InsecureConfigError(
            f"JWT_SECRET_KEY가 {state}. 이 키로 서명한 토큰은 누구나 위조할 수 있어요.\n"
            "  값 생성: python -c \"import secrets; print(secrets.token_urlsafe(48))\"\n"
            "  로컬은 infra/.env에, 운영은 배포 환경변수에 넣어주세요."
        )


def describe_database(engine: Engine) -> str:
    """접속 대상을 비밀번호 없이 한 줄로. 기동 로그에 찍어 개발/운영을 구분한다."""
    url = engine.url
    target = f"{url.host}:{url.port or 5432}/{url.database}"

    # Supabase pooler는 호스트가 개발·운영 공통이라 사용자명 접미사(project-ref)로만
    # 구분된다. 호스트만 찍으면 어느 쪽에 붙었는지 알 수 없다.
    if url.username and "." in url.username:
        target += f" [{url.username.split('.', 1)[1]}]"

    return target
