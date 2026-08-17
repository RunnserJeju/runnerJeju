# 배포 (Cloud Run + Supabase)

백엔드를 Google Cloud Run에, DB·Storage를 Supabase(서울, `ap-northeast-2`)에
올린다. 이 문서는 **"로컬에서는 멀쩡하던 게 Cloud Run에서 왜 문제가 되는가"** 를
우선순위 순으로 정리한다. 실제 배포는 명령어 절(맨 아래)을 따른다.

## 왜 로컬에선 문제가 없었나

로컬(`docker-compose`)이 조용했던 건 세 가지 전제 덕분이다.

1. 인스턴스가 **항상 1개 고정**
2. DB가 **같은 머신에 직접 연결**
3. 재시작해도 **나 혼자**라 충돌할 상대가 없음

Cloud Run은 이 셋을 전부 깬다 — 인스턴스가 트래픽에 따라 **복제되고**, DB가
**pooler 너머 원격**이고, **여러 컨테이너가 동시에** 뜬다. 그래서 그동안 잠자던
문제들이 깨어난다. 아래 P0~P3은 그 문제들을 "언제 터지는가" 기준으로 나눈 것이다.

---

## 🔴 P0 — 안 하면 배포하자마자 실패 (트래픽·스케일 무관)

인스턴스가 1개여도 터진다. **배포의 전제조건.**

### P0-1. Supabase pooler(6543, transaction mode)로 붙는다

Supabase **직접 연결**(`db.<ref>.supabase.co:5432`)은 현재 **IPv6 전용**이다.
그런데 Cloud Run 아웃바운드는 기본이 IPv4라, 직접 연결로는 **연결 자체가 안 된다.**
Supavisor pooler는 IPv4를 주므로 Cloud Run에서는 pooler가 사실상 필수다.

덤으로 pooler는 커넥션을 다중화해서, 인스턴스가 늘어도 실제 Postgres 백엔드
커넥션을 적게 유지해준다(→ P2와 연결).

```
# ✗ 직접 연결 (5432) — Cloud Run에서 IPv6 문제로 연결 실패
postgresql+psycopg://postgres.<ref>:PW@db.<ref>.supabase.co:5432/postgres

# ✓ transaction pooler (6543) — 이걸 DATABASE_URL로
postgresql+psycopg://postgres.<ref>:PW@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres
```

> 주소는 Supabase Dashboard → Project Settings → Database → **Connection string**
> 에서 그대로 복사하되, 스킴을 `postgresql+psycopg://` 로 바꾼다. Supabase 정책이
> 바뀌기도 하니 직접/pooler 주소는 대시보드에서 확인하는 게 안전하다.

### P0-2. `prepare_threshold=None` — prepared statement 끄기

우리는 `psycopg3`을 쓰는데, psycopg3은 자동으로 prepared statement를 만든다.
transaction pooler는 매 트랜잭션마다 다른 백엔드로 연결이 바뀔 수 있어서,
pooler를 통과하는 **첫 요청부터** `prepared statement already exists` 에러가 난다.
이건 스케일과 무관한 궁합 버그라 pooler를 쓰는 순간 무조건 꺼야 한다.

`app/db.py` 수정안 (P2의 `pool_size`도 함께):

```python
engine = create_engine(
    DATABASE_URL,
    pool_size=5,          # 인스턴스당 상시 5 (P2)
    max_overflow=5,       # 순간 피크에 +5 = 최대 10 (P2)
    pool_pre_ping=True,   # (유지) 죽은 커넥션 걸러냄
    pool_recycle=300,     # (유지)
    connect_args={"prepare_threshold": None},  # ★ pooler용: prepared statement 비활성화
)
```

> ⚠️ 이 코드 변경은 아직 반영하지 않았다. 로컬(직접 연결)에서도 `prepare_threshold=None`
> 은 무해하지만, `pool_size`/`max_overflow`는 배포 타이밍에 맞춰 반영한다.

### P0-3. 운영 환경변수를 빠짐없이 넣는다

개발과 운영이 **같은 이미지**를 쓰고 환경변수로만 갈린다. 값을 빠뜨리면 개발용
기본값이 그대로 운영에 실린다. `JWT_SECRET_KEY`가 없거나 개발 기본값이면
[`config_guard`](../server/app/config_guard.py)가 **기동을 거부**한다(누구나 관리자
토큰을 위조할 수 있기 때문). 이건 우리가 일부러 만든 안전장치다.

Cloud Run에 넣어야 할 값:

| 변수 | 용도 | 비고 |
| --- | --- | --- |
| `DATABASE_URL` | DB 접속 | P0-1의 pooler 주소 |
| `JWT_SECRET_KEY` | 로그인 토큰 서명 | 개발용과 **다른** 값. `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `SUPABASE_URL` | Storage API | `DATABASE_URL`과 같은 project-ref |
| `SUPABASE_API_SECRET_KEY` | Storage 업로드 | BYPASSRLS 키 — 절대 앱에 넣지 않고 서버 환경변수로만 |
| `SUPABASE_STORAGE_BUCKET` | 배너 버킷 | 예: `banners` |

> 비밀값(`JWT_SECRET_KEY`, `SUPABASE_API_SECRET_KEY`, `DATABASE_URL`의 비밀번호)은
> 평문 환경변수보다 **Secret Manager**에 넣고 참조하는 걸 권장한다.

---

## 🟠 P1 — 조용하다가 배포/장애 순간에 물림 (트래픽 무관)

### P1-1. 마이그레이션을 컨테이너 기동 경로에서 뗀다

지금 [`docker-entrypoint.sh`](../server/docker-entrypoint.sh)는 컨테이너가 뜰 때마다
`alembic upgrade head`를 실행한다. 로컬(컨테이너 1개)에선 안전하지만 Cloud Run에선
세 가지로 물린다.

1. **실패 시 전체 장애**: `set -e`라 마이그레이션이 실패하면 컨테이너가 안 뜬다.
   Cloud Run은 재시작만 반복하고 정상 인스턴스가 하나도 없어 서비스가 내려간다.
2. **롤백 불일치**: 앱을 이전 리비전으로 롤백해도 DB 스키마는 안 돌아간다.
   새 리비전이 앞으로 바꿔놓은 스키마 + 옛날 앱이 어긋난다.
3. **동시 부팅 레이스**: 여러 인스턴스가 동시에 콜드스타트하면 같은 마이그레이션을
   동시에 돌려 DDL이 충돌하거나 락 타임아웃이 난다.

**해결: "스키마 변경"과 "앱 기동"을 분리한다.** 우리 코드는 이미 절반 준비돼 있다.

- 마이그레이션은 배포 파이프라인에서 **앱을 띄우기 전에 한 번만** 돌린다
  (Cloud Run **Job** 또는 Cloud Build 스텝으로 `alembic upgrade head`).
- 앱 컨테이너 엔트리포인트에서는 `alembic upgrade head`를 **뺀다.**
- 대신 [`main.py`](../server/app/main.py)의 `schema_guard.verify(engine)`가 안전망이다 —
  스키마를 **바꾸지 않고 "맞는지 검사만"** 하고, 어긋나면 기동을 거부한다.
  → **"바깥에서 미리 마이그레이트 → 부팅 때는 검증만"** 이 정석 패턴.

> 베타(배포 드묾, min-instances=1)에선 3번 레이스는 드물지만, 1·2번은 트래픽과
> 무관하게 언제든 물릴 수 있어 우선순위 P1로 둔다.

---

## 🟡 P2 — 트래픽 늘어 인스턴스가 복제될 때만 (스케일아웃 전용)

### P2-1. `pool_size`를 작게, `max-instances`에 상한

인스턴스마다 자기 커넥션 풀을 따로 들고 DB에 붙는다. 그래서
**인스턴스 수 × 인스턴스당 커넥션 = DB가 받는 총 커넥션**이고, 곱셈이라 폭발한다.

지금 [`db.py`](../server/app/db.py)는 `pool_size`를 안 잡아 SQLAlchemy 기본값
(5 + overflow 10 = 인스턴스당 최대 15)이다. Cloud Run 기본 max-instances 100이면
이론상 1,500 커넥션 → Supabase 커넥션 한도를 넘겨 **DB가 먼저 죽는다.**

- 코드: P0-2의 diff대로 `pool_size=5, max_overflow=5` (인스턴스당 최대 10).
- 배포: `--max-instances`를 베타답게 **5~10**으로 묶는다 → 총 커넥션 100 이하로 관리.

> **베타 트래픽에선 안전하다.** 인스턴스가 1~2개면 15~30커넥션이 끝이라 DB가
> 끄떡없다. `max-instances` 상한만 걸어두면 당분간 여유. pool_size 미세튜닝은
> 실제로 오토스케일이 도는 걸 본 뒤에 해도 늦지 않다.

---

## ⚪ P3 — 아직 해당 없음 (기능·상황이 생기면)

### P3-1. 실시간(같이 뛰기)은 Cloud Run WebSocket 대신 Supabase Realtime

베타엔 실시간 기능이 없다. 나중에 넣을 때 Cloud Run WebSocket은 궁합이 나쁘다.

1. 요청 하나가 **최대 60분**이면 강제 종료 → 장시간 연결이 끊긴다.
2. 인스턴스가 수시로 늘었다 줄었다(0까지) 하는데, A인스턴스 유저와 B인스턴스
   유저는 **상태 공유가 안 된다** → Redis 같은 게 별도로 필요.
3. 그럼 FastAPI가 상태를 들게 되면서(stateful) Cloud Run의 stateless 전제가 깨진다.

→ 이미 있는 **Supabase Realtime**으로 넘기면 FastAPI는 stateless로 유지되고 이
세 문제가 통째로 사라진다.

### P3-2. 콜드스타트

우리 의존성은 가볍다(pandas 등 무거운 것 없음)라 콜드스타트는 거의 문제 안 된다.
`min-instances=1`만 켜두면 첫 요청 지연을 없앨 수 있다.

---

## 요약

| 우선순위 | 항목 | 언제 터지나 | 지금 할 일 |
| --- | --- | --- | --- |
| 🔴 P0 | pooler(6543) 연결 | 인스턴스 1개여도 | DATABASE_URL을 pooler 주소로 |
| 🔴 P0 | `prepare_threshold=None` | 인스턴스 1개여도 | db.py 수정 |
| 🔴 P0 | 운영 환경변수 | 기동 즉시 | Cloud Run에 5개 값 세팅 |
| 🟠 P1 | 마이그레이션 분리 | 배포·장애 시 | 기동에서 떼고 배포 스텝으로 |
| 🟡 P2 | pool_size / max-instances | 오토스케일 시 | max-instances 상한만 우선 |
| ⚪ P3 | 실시간 / 콜드스타트 | 기능 생기면 | 지금은 메모만 |

---

## 배포 명령어

> TODO: 동료 배포 작업 확정 후 실제 명령어(이미지 빌드 → 마이그레이션 Job →
> `gcloud run deploy` 옵션)를 채운다. 뼈대만 남겨둔다.

```bash
# 1. 이미지 빌드 & 푸시 (운영용은 --no-dev)
# 2. 마이그레이션을 앱 배포 전에 한 번 (Cloud Run Job 등)
#    alembic upgrade head
# 3. 앱 배포
#    gcloud run deploy runner-jeju-api \
#      --image ... \
#      --region asia-northeast3 \        # Cloud Run 서울
#      --min-instances 1 \
#      --max-instances 10 \
#      --set-secrets DATABASE_URL=...,JWT_SECRET_KEY=...,SUPABASE_API_SECRET_KEY=... \
#      --set-env-vars SUPABASE_URL=...,SUPABASE_STORAGE_BUCKET=banners
```
