"""원본 GPX(original_gpx)가 없는 코스를 채운다.

0028에서 original_gpx가 생기기 전에 올라간 코스는 원본이 NULL이라 GPX 내려받기가
안 된다. DB의 코스를 전부 돌며 NULL인 것만 채운다:

1. courses/courses.yaml에 같은 이름의 GPX가 있고, **그 파일로 지금 DB의 경로를
   만든 게 맞으면**(다시 리샘플한 결과가 path와 같으면) 파일을 그대로 넣는다.
2. 아니면 지금 path(15m 리샘플본)로 GPX를 지어 넣는다. 레포에 파일이 없는 코스
   (운영 웹으로 올린 코스)와, 운영 웹에서 경로를 교체해 레포 파일이 옛 버전이 된
   코스가 여기 온다. 원본이 아니라는 표시는 GPX `<metadata><desc>`에 남긴다.

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

RESAMPLED_NOTE = (
    "업로드 원본이 남아 있지 않아 앱이 쓰는 경로(15m 간격 리샘플본)로 만든 파일입니다."
)


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


def repo_original(course: Course, files_by_name: dict[str, Path]) -> bytes | None:
    """이 코스의 path를 만든 레포 GPX 파일 바이트. 없거나 다른 버전이면 None."""
    file = files_by_name.get(course.name)
    if file is None or not file.exists():
        return None
    content = file.read_bytes()
    resampled = [p.to_json() for p in gpx.parse(content).resampled_points]
    return content if same_path(course.path or [], resampled) else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    files_by_name = {
        entry["name"]: COURSES_DIR / entry["file"]
        for entry in load_manifest()
        if entry.get("name")
    }

    engine = create_engine(os.environ["DATABASE_URL"])
    from_file = from_path = skipped = 0

    with Session(engine) as db:
        for course in db.scalars(select(Course).order_by(Course.name)):
            if course.original_gpx:
                print(f"  건너뜀    {course.name}: 이미 원본이 있어요")
                skipped += 1
                continue
            if len(course.path or []) < 2:
                print(f"  건너뜀    {course.name}: 경로가 없어요")
                skipped += 1
                continue

            content = repo_original(course, files_by_name)
            if content is not None:
                source = f"레포 파일 {files_by_name[course.name].name}"
                from_file += 1
            else:
                content = gpx.build_gpx(
                    course.name, course.path, description=RESAMPLED_NOTE
                )
                source = f"리샘플 경로 {len(course.path)}점"
                from_path += 1

            print(f"  채움      {course.name}: {source} ({len(content):,}B)")
            if not args.dry_run:
                course.original_gpx = content

        summary = f"레포 파일 {from_file} · 리샘플 경로 {from_path} · 건너뜀 {skipped}"
        if args.dry_run:
            print(f"\n(dry-run) {summary}")
        else:
            db.commit()
            print(f"\n{summary}")


if __name__ == "__main__":
    main()
