"""courses/courses.yaml에 적힌 코스를 업로드 API로 올린다.

DB에 직접 쓰지 않고 API를 거치는 이유: 코스가 DB로 들어가는 경로를 하나로 유지하면
검증 규칙(GPX 파싱, 제주 경계 확인, 거리 계산)이 한 곳에만 있으면 된다. 스크립트가
DB에 직접 쓰면 그 규칙이 두 벌이 되고 언젠가 서로 어긋난다.

사용:
    python -m tools.push_courses              # 전부 업로드
    python -m tools.push_courses --dry-run    # 파싱만 하고 결과 출력
    python -m tools.push_courses sagye-coastal  # 특정 slug만
"""

import argparse
import os
import sys
from pathlib import Path

import httpx
import yaml

from app import gpx

COURSES_DIR = Path(__file__).resolve().parent.parent / "courses"
MANIFEST = COURSES_DIR / "courses.yaml"

DEFAULT_BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8000")

# courses.yaml에서 업로드 API 폼 필드로 그대로 넘기는 키.
# 거리/고도/순환 여부는 GPX에서 계산하므로 여기에 없다.
FORM_FIELDS = (
    "name",
    "description",
    "region",
    "difficulty",
    "estimated_duration_sec",
    "thumbnail_url",
)


def load_manifest() -> list[dict]:
    if not MANIFEST.exists():
        raise SystemExit(f"명단 파일이 없어요: {MANIFEST}")

    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}
    courses = data.get("courses") or []

    if not courses:
        raise SystemExit(f"{MANIFEST}에 코스가 없어요.")

    for entry in courses:
        for required in ("slug", "file"):
            if not entry.get(required):
                raise SystemExit(f"코스 항목에 '{required}'가 없어요: {entry}")

    return courses


def describe(entry: dict) -> str:
    """업로드하지 않고 파싱 결과만 보여준다."""
    path = COURSES_DIR / entry["file"]
    parsed = gpx.parse(path.read_bytes())

    gain = (
        "없음"
        if parsed.elevation_gain_meters is None
        else f"{parsed.elevation_gain_meters:.0f}m"
    )

    return (
        f"  {entry['slug']:<20} {entry.get('name') or parsed.name}\n"
        f"    좌표 {len(parsed.points)}개 · "
        f"{parsed.distance_meters / 1000:.2f}km · "
        f"고도상승 {gain} · "
        f"{'순환' if parsed.is_loop else '편도'}"
    )


def push(client: httpx.Client, entry: dict) -> str:
    path = COURSES_DIR / entry["file"]
    if not path.exists():
        raise SystemExit(f"GPX 파일이 없어요: {path}")

    form = {"slug": entry["slug"]}
    for key in FORM_FIELDS:
        value = entry.get(key)
        if value is not None:
            form[key] = str(value).strip()

    with path.open("rb") as handle:
        response = client.put(
            "/courses/gpx",
            data=form,
            files={"file": (path.name, handle, "application/gpx+xml")},
        )

    if response.status_code not in (200, 201):
        detail = response.text
        try:
            detail = response.json().get("detail", detail)
        except ValueError:
            pass
        raise SystemExit(f"[{entry['slug']}] 업로드 실패 ({response.status_code}): {detail}")

    course = response.json()
    action = "생성" if response.status_code == 201 else "갱신"

    return (
        f"  {action}  {course['slug']:<20} {course['name']} · "
        f"{course['distance_meters'] / 1000:.2f}km · "
        f"좌표 {len(course['path'])}개 · "
        f"{'순환' if course['is_loop'] else '편도'}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="코스 GPX를 업로드 API로 올린다.")
    parser.add_argument("slugs", nargs="*", help="지정하면 해당 slug만 처리")
    parser.add_argument("--dry-run", action="store_true", help="업로드 없이 파싱 결과만 출력")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    args = parser.parse_args()

    # 컨테이너/윈도 콘솔 모두에서 한글이 깨지지 않게.
    sys.stdout.reconfigure(encoding="utf-8")

    entries = load_manifest()
    if args.slugs:
        wanted = set(args.slugs)
        entries = [e for e in entries if e["slug"] in wanted]
        missing = wanted - {e["slug"] for e in entries}
        if missing:
            raise SystemExit(f"명단에 없는 slug: {', '.join(sorted(missing))}")

    if args.dry_run:
        print(f"파싱만 합니다 (업로드 없음) — {len(entries)}개")
        for entry in entries:
            print(describe(entry))
        return

    print(f"{args.base_url} 로 업로드 — {len(entries)}개")
    with httpx.Client(base_url=args.base_url, timeout=30) as client:
        for entry in entries:
            print(push(client, entry))


if __name__ == "__main__":
    main()
