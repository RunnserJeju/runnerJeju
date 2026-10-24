"""코스 카테고리 기본 스탬프 도안을 Storage 고정 경로에 올린다.

    python -m tools.upload_category_stamps <디렉터리>

디렉터리에 `art_run.png`, `road_run.png`, `trail_run.png`, `challenge_run.png`가 있어야 한다
(있는 것만 올린다). 경로는 app.stamp_images.category_object_path와 같다. 같은 경로를
덮어쓰므로 다시 올리면 앱이 캐시한 옛 그림이 한동안 남을 수 있다.
SUPABASE_URL / SUPABASE_API_SECRET_KEY 환경변수가 필요하다(api 컨테이너 안에서 돌린다).
"""

import sys
from pathlib import Path

from app import storage
from app.models import COURSE_CATEGORIES
from app.stamp_images import category_object_path


def main(directory: str) -> int:
    base = Path(directory)
    uploaded = 0
    for category in COURSE_CATEGORIES:
        file = base / f"{category}_run.png"
        if not file.is_file():
            print(f"skip {category}: {file} 없음")
            continue
        url = storage.upload_fixed(
            file.read_bytes(),
            path=category_object_path(category),
            content_type="image/png",
            bucket=storage.SUPABASE_STAMP_BUCKET,
        )
        print(f"{category}: {url}")
        uploaded += 1
    print(f"{uploaded}개 올림")
    return 0 if uploaded else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
