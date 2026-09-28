"""원본 GPX(original_gpx) 없이 올라간 코스에 레포의 GPX 파일을 채워 넣는다.

0028에서 original_gpx가 생기기 전에 올라간 코스는 원본이 NULL이라 GPX 내려받기가
안 된다. courses/courses.yaml의 파일로 이름을 맞춰 채운다.

**지금 DB의 경로를 만든 바로 그 파일일 때만** 채운다. 운영 웹에서 경로를 교체한
코스라면 레포 파일은 옛 버전이라, 그걸 원본이라고 내려주면 틀린 파일이 나간다.
그래서 파일을 다시 리샘플한 결과가 DB의 path와 같아야 쓴다.

  python -m tools.backfill_course_original_gpx            # 채우기
  python -m tools.backfill_course_original_gpx --dry-run  # 무엇이 채워질지만

이미 원본이 있는 코스는 건드리지 않는다.
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

# 좌표 비교 허용 오차(도). JSONB 왕복의 부동소수 끝자리 차이만 흡수한다(약 1cm).
_COORD_EPSILON = 1e-7


def load_manifest() -> list[dict]:
    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}
    return data.get("courses", data) if isinstance(data, dict) else data


def same_path(stored: list[dict], resampled: list[dict]) -> bool:
    if len(stored) != len(resampled):
        return False
    return all(
        abs(a["lat"] - b["lat"]) <= _COORD_EPSILON
        and abs(a["lng"] - b["lng"]) <= _COORD_EPSILON
        for a, b in zip(stored, resampled)
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    engine = create_engine(os.environ["DATABASE_URL"])
    filled = skipped = 0

    with Session(engine) as db:
        for entry in load_manifest():
            content = (COURSES_DIR / entry["file"]).read_bytes()
            parsed = gpx.parse(content)
            name = entry.get("name") or parsed.name

            courses = list(db.scalars(select(Course).where(Course.name == name)))
            if len(courses) != 1:
                print(f"  건너뜀  {name}: 같은 이름의 코스가 {len(courses)}개예요")
                skipped += 1
                continue
            course = courses[0]

            if course.original_gpx:
                print(f"  건너뜀  {name}: 이미 원본이 있어요")
                skipped += 1
                continue

            resampled = [p.to_json() for p in parsed.resampled_points]
            if not same_path(course.path or [], resampled):
                print(f"  건너뜀  {name}: DB 경로가 이 파일로 만든 게 아니에요(교체됐을 수 있음)")
                skipped += 1
                continue

            print(f"  채움    {name}: {entry['file']} ({len(content):,}B)")
            if not args.dry_run:
                course.original_gpx = content
            filled += 1

        if args.dry_run:
            print(f"\n(dry-run) 채움 {filled} · 건너뜀 {skipped}")
        else:
            db.commit()
            print(f"\n채움 {filled} · 건너뜀 {skipped}")


if __name__ == "__main__":
    main()
