"""운영자 계정을 DB에 직접 시드한다(운영 웹 세션 로그인용).

가입 API가 없다 — 운영자는 소수이고 신뢰된 사람이라, HTTP를 거치지 않고 이
로컬 일회성 스크립트로 만든다(tools/push_courses.py와 같은 방침). 비밀번호는
CLI 인자로 받지 않고 항상 프롬프트로 입력받아 셸 히스토리에 남지 않게 한다.

DATABASE_URL이 API 서버와 같은 값으로 잡혀 있어야 한다(docker compose exec api로
컨테이너 안에서 실행하면 이미 그렇다).

사용:
    python -m tools.create_admin                  # 대화형으로 아이디/비번 입력
    python -m tools.create_admin --username jeju  # 아이디만 인자로, 비번은 프롬프트
"""

import argparse
import getpass
import sys

from sqlalchemy import select

from app.admin.security import BCRYPT_MAX_PASSWORD_BYTES, hash_password
from app.db import SessionLocal
from app.models import AdminUser

USERNAME_MAX = 50


def _prompt_username(preset: str | None) -> str:
    username = (preset or input("운영자 아이디: ")).strip()
    if not username:
        sys.exit("아이디가 비어 있어요.")
    if len(username) > USERNAME_MAX:
        sys.exit(f"아이디는 {USERNAME_MAX}자를 넘을 수 없어요.")
    return username


def _prompt_password() -> str:
    password = getpass.getpass("비밀번호: ")
    if not password:
        sys.exit("비밀번호가 비어 있어요.")
    # bcrypt는 72바이트까지만 본다 — 그 이상은 조용히 잘려 위험하므로 여기서 막는다.
    if len(password.encode("utf-8")) > BCRYPT_MAX_PASSWORD_BYTES:
        sys.exit(f"비밀번호는 {BCRYPT_MAX_PASSWORD_BYTES}바이트를 넘을 수 없어요.")
    if getpass.getpass("비밀번호 확인: ") != password:
        sys.exit("두 번 입력한 비밀번호가 달라요.")
    return password


def main() -> None:
    parser = argparse.ArgumentParser(description="운영자 계정 생성/비밀번호 재설정")
    parser.add_argument("--username", help="운영자 아이디(생략하면 프롬프트)")
    parser.add_argument("--display-name", help="표시 이름(선택)")
    args = parser.parse_args()

    username = _prompt_username(args.username)

    with SessionLocal() as db:
        existing = db.execute(
            select(AdminUser).where(AdminUser.username == username)
        ).scalar_one_or_none()

        if existing is not None:
            answer = input(
                f"'{username}' 계정이 이미 있어요. 비밀번호를 재설정할까요? [y/N] "
            ).strip().lower()
            if answer != "y":
                sys.exit("취소했어요.")
            password = _prompt_password()
            existing.password_hash = hash_password(password)
            if args.display_name:
                existing.display_name = args.display_name
            # 재설정 시 비활성 상태였다면 되살린다.
            existing.disabled_at = None
            db.commit()
            print(f"'{username}' 비밀번호를 재설정했어요.")
            return

        password = _prompt_password()
        db.add(
            AdminUser(
                username=username,
                password_hash=hash_password(password),
                display_name=args.display_name,
            )
        )
        db.commit()
        print(f"운영자 '{username}' 계정을 만들었어요.")


if __name__ == "__main__":
    main()
