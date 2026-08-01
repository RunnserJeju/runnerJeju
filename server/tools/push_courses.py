"""courses/courses.yaml에 적힌 코스를 DB에 직접 업로드한다.

API(HTTP)를 거치지 않는다 — 이 스크립트는 로그인 세션이 없는 로컬 일회성
도구라, 애초에 인증할 대상이 없다. 대신 `app.routers.courses`의
`upsert_course_from_gpx_bytes`를 이 프로세스 안에서 직접 호출해 DB에 쓴다.
`PUT /courses/gpx` 라우터가 쓰는 것과 정확히 같은 함수라서, 검증 규칙(GPX
파싱, slug 처리)이 API용과 스크립트용으로 두 벌 갈라지지 않는다.

DATABASE_URL이 API 서버와 같은 값으로 잡혀 있어야 한다 (docker compose exec
api로 컨테이너 안에서 실행하면 이미 그렇다).

사용:
    python -m tools.push_courses              # 전부 업로드
    python -m tools.push_courses --dry-run    # 파싱만 하고 결과 출력
    python -m tools.push_courses sagye-coastal  # 특정 slug만
"""

import argparse
import sys
from pathlib import Path

import yaml
from sqlalchemy.orm import Session

from app import gpx
from app.db import SessionLocal
from app.routers.courses import CourseUploadError, upsert_course_from_gpx_bytes

COURSES_DIR = Path(__file__).resolve().parent.parent / "courses"
MANIFEST = COURSES_DIR / "courses.yaml"

# courses.yaml에서 upsert_course_from_gpx_bytes에 그대로 넘기는 키.
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


def push(db: Session, entry: dict) -> str:
    path = COURSES_DIR / entry["file"]
    if not path.exists():
        raise SystemExit(f"GPX 파일이 없어요: {path}")

    kwargs = {key: entry.get(key) for key in FORM_FIELDS}
    kwargs["difficulty"] = kwargs.get("difficulty") or "normal"

    try:
        course, is_new = upsert_course_from_gpx_bytes(
            db,
            path.read_bytes(),
            slug=entry["slug"],
            created_by="seed-script",
            **kwargs,
        )
    except CourseUploadError as exc:
        raise SystemExit(f"[{entry['slug']}] 업로드 실패: {exc}") from exc

    action = "생성" if is_new else "갱신"

    return (
        f"  {action}  {course.slug:<20} {course.name} · "
        f"{course.distance_meters / 1000:.2f}km · "
        f"좌표 {len(course.path)}개 · "
        f"{'순환' if course.is_loop else '편도'}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="코스 GPX를 DB에 직접 업로드한다.")
    parser.add_argument("slugs", nargs="*", help="지정하면 해당 slug만 처리")
    parser.add_argument("--dry-run", action="store_true", help="업로드 없이 파싱 결과만 출력")
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

    print(f"DB에 직접 업로드 — {len(entries)}개")
    db = SessionLocal()
    try:
        for entry in entries:
            print(push(db, entry))
    finally:
        db.close()


if __name__ == "__main__":
    main()
