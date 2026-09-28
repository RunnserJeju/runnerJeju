"""제주 베이스맵 데이터를 앱이 읽을 바이너리로 굽는다.

Overpass로 받은 OSM 원본(coastline/roads/places.json)을 단순화해 압축한다.
데이터를 갱신하려면 Overpass에서 다시 받아 이 스크립트를 돌린다.

해안선은 **닫힌 고리로 이어 붙여서** 내보낸다. OSM 해안선은 조각조각 나뉘어
있어서 그대로는 "뭍이 어디인지"를 알 수 없다. 앱에서 조각을 잇는 건 화면 밖까지
따라가야 하는 일이라, 섬 하나짜리 데이터를 다루는 여기서 끝낸다. 제주의
해안선 조각 112개는 빈틈없이 57개 고리로 닫힌다(본섬·우도·마라도·부속 섬들).

도로는 골목·등산로까지 전부 담는다. 큰길만 넣으면 지도가 텅 비어 보이고,
"어디를 달렸는지"를 말해 주지 못한다.

way마다 경계 상자를 앞에 둔다. 앱은 카드 한 장에 3~6km만 그리는데, 상자가
없으면 화면 밖 제주 반대편 골목까지 전부 좌표 변환하게 된다. 상자를 먼저
비교하면 실제로 변환할 것은 수십 개로 줄어든다.

형식(v3, little-endian):
  "RJGE" u8:version u8:layerCount
  layer × N: u8:id u8:closed u32:wayCount
      way × M: i32:minLat i32:minLon i32:maxLat i32:maxLon   (경계 상자)
               u16:pointCount i32:lat0 i32:lon0  (1e-5도)
               (pointCount-1) × (i16:dLat i16:dLon)
  u16:labelCount
  label × K: i32:lat i32:lon u8:kind u8:nameLen  name(utf8)

closed=1인 레이어는 마지막 점과 첫 점이 이어진 것으로 보고 칠한다.
(중복되는 끝점은 빼고 저장한다.)
"""
import collections
import json, math, os, struct

SP = os.environ['SP']
SCALE = 100000.0           # 1e-5도 ≈ 1.1m
TOL = 5.0                  # 단순화 허용오차(m)
I16 = 32767

LAT0 = 33.38
MLAT = 111132.92 - 559.82*math.cos(math.radians(2*LAT0)) + 1.175*math.cos(math.radians(4*LAT0))
MLNG = 111412.84*math.cos(math.radians(LAT0)) - 93.5*math.cos(math.radians(3*LAT0))

def load(name):
    return json.load(open(f'{SP}/osm/{name}.json'))['elements']

def rdp(pts, tol):
    if len(pts) < 3: return pts
    keep = [False]*len(pts); keep[0] = keep[-1] = True
    stack = [(0, len(pts)-1)]
    def xy(p): return (p[1]*MLNG, p[0]*MLAT)
    while stack:
        s, e = stack.pop()
        ax, ay = xy(pts[s]); bx, by = xy(pts[e])
        dx, dy = bx-ax, by-ay; L = dx*dx + dy*dy
        far, idx = 0.0, -1
        for i in range(s+1, e):
            px, py = xy(pts[i])
            if L == 0: d = math.hypot(px-ax, py-ay)
            else:
                t = max(0.0, min(1.0, ((px-ax)*dx + (py-ay)*dy)/L))
                d = math.hypot(px-(ax+t*dx), py-(ay+t*dy))
            if d > far: far, idx = d, i
        if idx != -1 and far > tol:
            keep[idx] = True; stack.append((s, idx)); stack.append((idx, e))
    return [p for p, k in zip(pts, keep) if k]

def stitch_rings(elements):
    """해안선 조각을 끝점끼리 이어 닫힌 고리로 만든다."""
    ways = []
    for e in elements:
        g = e.get('geometry') or []
        pts = [(round(p['lat'], 7), round(p['lon'], 7)) for p in g if p]
        if len(pts) >= 2:
            ways.append(pts)

    by_start = collections.defaultdict(list)
    for i, w in enumerate(ways):
        by_start[w[0]].append(i)

    used = [False] * len(ways)
    rings, dangling = [], 0
    for i, w in enumerate(ways):
        if used[i]:
            continue
        used[i] = True
        chain = list(w)
        while chain[0] != chain[-1]:
            nxt = [j for j in by_start.get(chain[-1], []) if not used[j]]
            if not nxt:
                break
            j = nxt[0]
            used[j] = True
            chain.extend(ways[j][1:])
        if chain[0] == chain[-1]:
            rings.append(chain[:-1])   # 중복 끝점 제거
        else:
            dangling += 1
    if dangling:
        raise SystemExit(f'닫히지 않은 해안선 조각 {dangling}개 — 데이터를 확인하세요')
    return rings


def quantize(pts):
    return [(round(la*SCALE), round(lo*SCALE)) for la, lo in pts]

def split_for_i16(q):
    """i16 델타 범위를 넘는 자리에서 선을 나눈다."""
    out, cur = [], [q[0]]
    for prev, p in zip(q, q[1:]):
        if abs(p[0]-prev[0]) > I16 or abs(p[1]-prev[1]) > I16:
            if len(cur) >= 2: out.append(cur)
            cur = [p]
        else:
            cur.append(p)
    if len(cur) >= 2: out.append(cur)
    return out

def ways_from(elements, pred=None):
    out = []
    for e in elements:
        if pred and not pred(e): continue
        g = e.get('geometry') or []
        pts = [(p['lat'], p['lon']) for p in g if p]
        if len(pts) < 2: continue
        s = rdp(pts, TOL)
        if len(s) < 2: continue
        # 양자화 후 같은 점이 붙으면 걷어낸다
        q = quantize(s); dedup = [q[0]]
        for p in q[1:]:
            if p != dedup[-1]: dedup.append(p)
        if len(dedup) < 2: continue
        out.extend(split_for_i16(dedup))
    return out

rings = stitch_rings(load('coastline'))
coast = []
for ring in rings:
    s = rdp(ring, TOL)
    if len(s) < 3:
        continue
    q = quantize(s)
    dedup = [q[0]]
    for p in q[1:]:
        if p != dedup[-1]:
            dedup.append(p)
    if len(dedup) >= 3:
        # 고리는 나누면 안 된다. i16 범위를 넘는 자리가 있으면 그 고리는 버린다
        # (그런 고리는 화면 하나에 담기지도 않을 만큼 크다).
        ok = all(
            abs(b[0] - a[0]) <= I16 and abs(b[1] - a[1]) <= I16
            for a, b in zip(dedup, dedup[1:] + dedup[:1])
        )
        if ok:
            coast.append(dedup)
roads = load('roads_all')

# 굵기 세 단계. 지도가 한 덩어리로 보이지 않게 위계를 준다.
MAJOR = {'motorway', 'trunk', 'primary', 'secondary'}
MID = {'tertiary', 'unclassified', 'residential', 'living_street'}

major = ways_from(roads, lambda e: e['tags'].get('highway') in MAJOR)
mid = ways_from(roads, lambda e: e['tags'].get('highway') in MID)
minor = ways_from(roads, lambda e: e['tags'].get('highway') not in MAJOR | MID)

KIND = {'city': 0, 'town': 1, 'village': 2, 'suburb': 3, 'island': 4, 'peak': 5}
labels = []
for e in load('places'):
    t = e.get('tags', {})
    name = t.get('name')
    if not name or len(name) > 20: continue
    kind = 'peak' if t.get('natural') == 'peak' else t.get('place')
    if kind not in KIND: continue
    labels.append((round(e['lat']*SCALE), round(e['lon']*SCALE), KIND[kind], name))

buf = bytearray()
buf += b'RJGE' + struct.pack('<BB', 3, 4)
LAYERS = ((0, 1, coast), (1, 0, major), (2, 0, mid), (3, 0, minor))
for layer_id, closed, ways in LAYERS:
    buf += struct.pack('<BBI', layer_id, closed, len(ways))
    for w in ways:
        lats = [p[0] for p in w]
        lons = [p[1] for p in w]
        buf += struct.pack('<iiii', min(lats), min(lons), max(lats), max(lons))
        buf += struct.pack('<Hii', len(w), w[0][0], w[0][1])
        for prev, p in zip(w, w[1:]):
            buf += struct.pack('<hh', p[0]-prev[0], p[1]-prev[1])
buf += struct.pack('<H', len(labels))
for la, lo, kind, name in labels:
    nb = name.encode('utf-8')
    buf += struct.pack('<iiBB', la, lo, kind, len(nb)) + nb

out = f'{SP}/osm/jeju_basemap.bin'
open(out, 'wb').write(buf)
print(
    f'해안선 {len(coast)}고리 / 큰길 {len(major)}선 / 마을길 {len(mid)}선 / '
    f'좁은길·산길 {len(minor)}선 / 라벨 {len(labels)}개'
)
print(f'→ {len(buf)/1024:.0f} KB  ({out})')
