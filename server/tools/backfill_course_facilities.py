"""옛 단일 주소 컬럼(parking_address/restroom_address)을 parkings/restrooms JSONB로 옮긴다.

0009에서 JSONB를 추가했지만 그 전에 올라간 코스의 주차장/화장실은 옛 컬럼에만 남아
있었다. 앱은 이제 JSONB만 읽으므로(지도 마커·시트·상세 모두) 옮기지 않으면 그 코스들의
주차장/화장실이 '정보 없음'이 된다. 옛 컬럼을 지우는 마이그레이션도 이 백필이 끝나야
돌릴 수 있다(옛 컬럼에만 값이 있는 행이 있으면 스스로 멈춘다).

  python -m tools.backfill_course_facilities            # 적용
  python -m tools.backfill_course_facilities --dry-run  # 무엇이 들어갈지만

규칙:
  - 그 종류의 JSONB가 비어 있을 때만 채운다. 이미 운영 웹으로 넣은 값은 건드리지 않는다
    (그래서 여러 번 돌려도 같다).
  - 옛 값은 손으로 적은 문자열이라 한 칸에 주소가 쉼표로 여럿 있거나("김녕로14길 6,
    김녕로 209") 장소명이 붙어 있다("월드컵경기장 서귀포시 법환동 870"). 쉼표로 나누고,
    통째로 좌표를 못 찾으면 앞/뒤 단어를 떼어 가며 다시 찾는다. 떼어낸 말은 시설 이름으로
    살린다.
  - 주소는 운영 웹 "좌표 확인"과 같게 카카오가 정규화한 값(도로명 우선)으로 저장한다.
  - 원문 그대로 찾지 못했거나 후보가 여럿이면 "확인 필요"로 표시한다 — 결과가 틀렸으면
    운영 웹에서 그 코스만 고치면 된다.
  - 끝내 좌표를 못 찾은 주소가 있는 코스는 그 종류를 통째로 건너뛴다(일부만 넣으면
    "다 옮겨졌다"로 오해하기 쉽다).

옛 컬럼은 ORM 모델에서 빠졌으므로 여기서는 SQL로 직접 읽고 쓴다.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass

from sqlalchemy import create_engine, text

from app import geocoding

# (옛 컬럼, JSONB 컬럼, 표시 이름)
KINDS = (
    ("parking_address", "parkings", "주차장"),
    ("restroom_address", "restrooms", "화장실"),
)


@dataclass
class Resolved:
    facility: dict
    # 원문 그대로가 아니라 단어를 떼어 찾았거나, 후보가 여럿이었으면 사람이 봐야 한다.
    needs_review: bool
    note: str


def _clean(raw: str) -> str:
    # \xa0(줄바꿈 없는 공백)이 섞인 값이 있다. 공백을 하나로 모은다.
    return " ".join(raw.replace("\xa0", " ").split())


def _split(raw: str) -> list[str]:
    return [part for part in (_clean(p) for p in raw.split(",")) if part]


def _attempts(address: str) -> list[tuple[str, str | None]]:
    """(검색할 주소, 떼어낸 말) 후보. 원문 → 앞 단어 떼기 → 뒤 단어 떼기 순."""
    words = address.split()
    attempts: list[tuple[str, str | None]] = [(address, None)]
    for i in range(1, len(words) - 1):
        attempts.append((" ".join(words[i:]), " ".join(words[:i])))
    for i in range(len(words) - 1, 1, -1):
        attempts.append((" ".join(words[:i]), " ".join(words[i:])))
    return attempts


def resolve(address: str) -> Resolved | None:
    for query, dropped in _attempts(address):
        results = geocoding.geocode(query)
        if not results:
            continue
        top = results[0]
        notes = []
        if dropped:
            notes.append(f"'{dropped}' 떼고 찾음")
        if len(results) > 1:
            notes.append(f"후보 {len(results)}개 중 첫째")
        return Resolved(
            facility={
                "name": dropped,
                "address": top.road_address or top.address,
                "lat": top.lat,
                "lng": top.lng,
            },
            needs_review=bool(notes),
            note=", ".join(notes),
        )
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    engine = create_engine(os.environ["DATABASE_URL"])
    filled = review = skipped = 0

    with engine.begin() as conn:
        rows = conn.execute(
            text(
                "SELECT id, name, parking_address, restroom_address, parkings, restrooms "
                "FROM courses ORDER BY name"
            )
        ).mappings().all()

        for row in rows:
            for old, new, label in KINDS:
                raw = row[old]
                if not raw or not raw.strip():
                    continue
                if row[new]:
                    print(f"  유지      {row['name']} [{label}] JSONB에 이미 {len(row[new])}개 — 옛 값 무시: {raw!r}")
                    continue

                facilities: list[dict] = []
                failed: list[str] = []
                for address in _split(raw):
                    resolved = resolve(address)
                    if resolved is None:
                        failed.append(address)
                        continue
                    facilities.append(resolved.facility)
                    mark = "확인 필요" if resolved.needs_review else "OK"
                    review += resolved.needs_review
                    f = resolved.facility
                    print(
                        f"  {mark:<8}  {row['name']} [{label}] {address!r}\n"
                        f"            → {f['name'] or '-'} | {f['address']} ({f['lat']:.6f}, {f['lng']:.6f})"
                        + (f"  ※ {resolved.note}" if resolved.note else "")
                    )

                if failed:
                    print(f"  건너뜀    {row['name']} [{label}] 좌표를 못 찾은 주소: {failed}")
                    skipped += 1
                    continue

                if not args.dry_run:
                    conn.execute(
                        text(f"UPDATE courses SET {new} = CAST(:value AS jsonb) WHERE id = :id"),
                        {"value": json.dumps(facilities, ensure_ascii=False), "id": row["id"]},
                    )
                filled += 1

        summary = f"채움 {filled} · 확인 필요 {review} · 건너뜀 {skipped}"
        if args.dry_run:
            print(f"\n(dry-run, 아무것도 쓰지 않음) {summary}")
        else:
            print(f"\n{summary}")


if __name__ == "__main__":
    main()
