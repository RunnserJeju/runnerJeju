"""이미 올라간 코스의 경로(path)만 GPX에서 다시 만들어 제자리에 덮어쓴다.

경로 저장 형식이 바뀌었을 때 쓴다 — 처음 쓴 계기는 고도다. 코스들이 고도를
버리던 시절에 올라가서, 앱의 고도 그래프가 그릴 것이 없었다.

push_courses(seed)로는 안 된다. 그건 매번 새 코스를 만들고, courses를 비우고
다시 올리면 그동안 관리자가 손본 썸네일·소요시간과 러닝 기록·찜·스탬프가
가리키는 course_id가 전부 끊긴다. 그래서 이름으로 짝을 맞춰 path만 바꾼다.

  python -m tools.backfill_course_paths            # 전부
  python -m tools.backfill_course_paths --dry-run  # 무엇이 바뀔지만

짝을 못 맞추거나 점 개수가 다르면 그 코스는 건너뛰고 알린다. 점 개수가 다르다는
건 리샘플 규칙이 바뀌었거나 GPX 파일이 교체된 것이라, 조용히 덮어쓸 일이 아니다.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import yaml
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app import gpx
from app.models import Course

COURSES_DIR = Path(__file__).resolve().parent.parent / "courses"
MANIFEST = COURSES_DIR / "courses.yaml"


def load_manifest() -> list[dict]:
    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}
    return data.get("courses", data) if isinstance(data, dict) else data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    engine = create_engine(os.environ["DATABASE_URL"])
    updated = skipped = 0

    with Session(engine) as db:
        for entry in load_manifest():
            parsed = gpx.parse((COURSES_DIR / entry["file"]).read_bytes())
            name = entry.get("name") or parsed.name
            new_path = [p.to_json() for p in parsed.resampled_points]

            course = db.scalar(select(Course).where(Course.name == name))
            if course is None:
                print(f"  건너뜀  {name}: DB에 같은 이름의 코스가 없어요")
                skipped += 1
                continue
            if len(course.path or []) != len(new_path):
                print(
                    f"  건너뜀  {name}: 점 개수가 달라요 "
                    f"(DB {len(course.path or [])} / GPX {len(new_path)})"
                )
                skipped += 1
                continue

            had_alt = "altitude" in (course.path or [{}])[0]
            has_alt = "altitude" in new_path[0]
            print(
                f"  갱신    {name}: {len(new_path)}점, "
                f"고도 {'있음' if had_alt else '없음'} → {'있음' if has_alt else '없음'}"
            )
            if not args.dry_run:
                course.path = new_path
            updated += 1

        if args.dry_run:
            print(f"\n(dry-run) 갱신 {updated} · 건너뜀 {skipped}")
        else:
            db.commit()
            print(f"\n갱신 {updated} · 건너뜀 {skipped}")


if __name__ == "__main__":
    main()
