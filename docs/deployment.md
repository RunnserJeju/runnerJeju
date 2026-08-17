# 배포 (Cloud Run + Supabase)

백엔드를 Google Cloud Run(서울, `asia-northeast3`)에, DB·Storage를 Supabase(서울,
`ap-northeast-2`)에 올린다. 이 문서는 **지금 당장 배포하기 위해 반드시 해야 할 것**을
위에, **나중에 트래픽·기능이 늘면 생길 문제**를 아래에 둔다.

## 왜 로컬에선 문제가 없었나 (멘탈모델)

로컬(`docker-compose`)이 조용했던 건 세 전제 덕분이다.

1. 인스턴스가 **항상 1개 고정**
2. DB가 **같은 머신에 직접 연결**
3. 재시작해도 **나 혼자**라 충돌할 상대가 없음

Cloud Run은 셋을 다 깬다 — DB가 **pooler 너머 원격**(②)이고, 여러 컨테이너가
**동시에** 뜨고(③), 트래픽에 따라 **복제된다**(①). 아래 "지금 당장"은 ②③에서
오는, **인스턴스가 1개여도 터지는** 문제들이다. ①에서 오는 문제는 스케일이 실제로
돌 때만 터지므로 문서 아래쪽으로 뺐다.

---

# 지금 당장 — 배포하려면 이것부터

인스턴스 1개여도 안 하면 못 뜨거나 첫 요청부터 터진다. **배포의 전제조건.**

## 1. DATABASE_URL을 pooler(6543, transaction mode)로

Supabase **직접 연결**(`db.<ref>.supabase.co:5432`)은 현재 **IPv6 전용**인데,
Cloud Run 아웃바운드는 기본 IPv4라 **연결 자체가 안 된다.** Supavisor pooler는
IPv4를 주므로 Cloud Run에선 pooler가 사실상 필수다.

```
# ✗ 직접 연결 (5432) — Cloud Run에서 IPv6로 연결 실패
postgresql+psycopg://postgres.<ref>:PW@db.<ref>.supabase.co:5432/postgres

# ✓ transaction pooler (6543) — 이걸 DATABASE_URL로
postgresql+psycopg://postgres.<ref>:PW@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres
```

> 주소는 Supabase Dashboard → Project Settings → Database → **Connection string**에서
> 복사하되 스킴을 `postgresql+psycopg://`로 바꾼다. 사용자명이 `postgres.<ref>`
> 형식이어야 pooler가 우리 프로젝트로 라우팅한다. Supabase 정책이 바뀌기도 하니
> 직접/pooler 주소는 대시보드에서 확인하는 게 안전하다.

## 2. `prepare_threshold=None` — prepared statement 끄기 (db.py 수정)

`psycopg3`은 자동으로 prepared statement를 만든다. transaction pooler는 매
트랜잭션마다 다른 백엔드로 연결이 바뀔 수 있어, pooler를 통과하는 **첫 요청부터**
`prepared statement already exists`가 난다. 스케일과 무관한 궁합 버그라 pooler를
쓰는 순간 무조건 꺼야 한다.

현재 [`db.py`](../server/app/db.py)는 `connect_args`가 없다. 아래로 바꾼다.

```python
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,   # (유지) 죽은 커넥션 걸러냄
    pool_recycle=300,     # (유지)
    connect_args={"prepare_threshold": None},  # ★ pooler용: prepared statement 비활성화
)
```

> 로컬(직접 연결)에서도 `prepare_threshold=None`은 무해하므로 지금 반영해도 된다.
> `pool_size`는 지금 만지지 않는다(이유는 아래 "커넥션 폭발" 참고).

## 3. 운영 환경변수 세팅

개발과 운영이 **같은 이미지**를 쓰고 환경변수로만 갈린다. Cloud Run에 넣을 값:

| 변수 | 용도 | 빠뜨리면 |
| --- | --- | --- |
| `DATABASE_URL` | DB 접속 (1의 pooler 주소) | 기본값이 `localhost`라 Cloud Run에선 **아예 못 뜸** |
| `JWT_SECRET_KEY` | 로그인 토큰 서명 | **조용히 뜬 뒤** 누구나 관리자 토큰 위조 가능 |
| `SUPABASE_URL` | Storage API (같은 project-ref) | Storage 호출 시 실패 |
| `SUPABASE_API_SECRET_KEY` | Storage 업로드 (BYPASSRLS 키) | **업로드 시점에야** 터짐 |
| `SUPABASE_STORAGE_BUCKET` | 배너 버킷 (예: `banners`) | 업로드 시점에 터짐 |

**JWT만 조용히 뜬다**는 게 핵심이다. 나머지는 빠뜨리면 바로/곧 티가 나지만
`JWT_SECRET_KEY`는 개발 기본값 그대로도 서버가 멀쩡히 떠버린다. 그래서 이 키만
[`config_guard`](../server/app/config_guard.py)가 **기동을 거부**한다(우리가 일부러
넣은 안전장치). 즉 config_guard는 5개를 다 검사하는 게 아니라 JWT 하나를 막는다.

> `JWT_SECRET_KEY` 값 생성: `python -c "import secrets; print(secrets.token_urlsafe(48))"` (개발용과 **다른** 값)
>
> 비밀값(`JWT_SECRET_KEY`, `SUPABASE_API_SECRET_KEY`, `DATABASE_URL`의 비밀번호)은
> 평문 환경변수보다 **Secret Manager**에 넣고 참조하는 걸 권장한다.

## 4. 마이그레이션을 컨테이너 기동에서 뗀다

지금 [`docker-entrypoint.sh`](../server/docker-entrypoint.sh)는 컨테이너가 뜰 때마다
`alembic upgrade head`를 돌린다(`set -e`). 로컬(1개)에선 안전하지만 Cloud Run에선
물린다.

1. **실패 시 전체 장애**: 마이그레이션이 실패하면 컨테이너가 안 뜨고, Cloud Run은
   재시작만 반복해 정상 인스턴스가 하나도 없어진다.
2. **롤백 불일치**: 앱을 이전 리비전으로 롤백해도 DB 스키마는 안 돌아간다.
3. (동시 부팅 레이스는 스케일 얘기라 아래로 뺀다.)

**해결: "스키마 변경"과 "앱 기동"을 분리한다.** 코드는 이미 절반 준비돼 있다.

- 마이그레이션은 배포 파이프라인에서 **앱을 띄우기 전에 한 번만** 돌린다
  (Cloud Run **Job** 또는 Cloud Build 스텝으로 `alembic upgrade head`).
- 앱 컨테이너 엔트리포인트에서는 `alembic upgrade head`를 **뺀다.**
- 대신 [`schema_guard.verify(engine)`](../server/app/schema_guard.py)가 안전망이다 —
  `alembic_version`을 **읽어 비교만** 하고(DB를 바꾸지 않음) 어긋나면 기동을 거부한다.
  → **"바깥에서 미리 마이그레이트 → 부팅 때는 검증만"** 이 정석 패턴.

## 5. 배포 명령어

> TODO: 동료 배포 작업 확정 후 이미지 빌드 → 마이그레이션 Job → `gcloud run deploy`
> 실제 값을 채운다. 뼈대만 남긴다.

```bash
# 1. 이미지 빌드 & 푸시 (운영용은 --no-dev)
# 2. 마이그레이션을 앱 배포 전에 한 번 (Cloud Run Job 등)
#    alembic upgrade head
# 3. 앱 배포
#    gcloud run deploy runner-jeju-api \
#      --image ... \
#      --region asia-northeast3 \        # Cloud Run 서울
#      --min-instances 1 \              # 콜드스타트 제거 (단, 상시 1개 = 상시 과금)
#      --max-instances 10 \             # 커넥션 상한용 (아래 "커넥션 폭발" 참고)
#      --set-secrets DATABASE_URL=...,JWT_SECRET_KEY=...,SUPABASE_API_SECRET_KEY=... \
#      --set-env-vars SUPABASE_URL=...,SUPABASE_STORAGE_BUCKET=banners
```

## 지금 당장 체크리스트

- [ ] `DATABASE_URL`을 pooler(6543) 주소로
- [ ] `db.py`에 `connect_args={"prepare_threshold": None}`
- [ ] 운영 환경변수 5개 세팅 (JWT는 개발과 다른 값)
- [ ] 엔트리포인트에서 `alembic upgrade head` 제거 + 배포 스텝으로 이동
- [ ] `--min-instances 1`, `--max-instances 10`

---

# 나중에 — 트래픽·기능이 늘면 생길 문제

지금 베타 트래픽에선 안 터진다. 상황이 오면 손대는 항목이다. **지금은 "이런 게
터진다"만 기억**하면 된다.

## 커넥션 폭발 (인스턴스가 복제되기 시작하면)

인스턴스마다 자기 커넥션 풀을 들고 pooler에 붙는다. **인스턴스 수 × 인스턴스당
커넥션**으로 늘어나므로, 오토스케일이 크게 돌면 pooler의 client 슬롯 한도를 넘겨
새 커넥션이 거부될 수 있다. (pooler가 뒤에서 실제 Postgres 백엔드 커넥션은 낮게
유지해주므로, 터지는 건 Postgres가 아니라 **pooler 앞단**이다.)

- **지금 대비**: `--max-instances`를 5~10으로 묶어 총량을 관리(위 명령어에 반영됨).
- **그때 할 일**: `db.py`의 `pool_size`/`max_overflow`를 인스턴스당 작게(예: 5/5)
  잡아 곱셈의 밑을 줄인다. 실제 오토스케일이 도는 걸 본 뒤 튜닝해도 늦지 않다.

## 동시 부팅 레이스 (콜드스타트가 잦아지면)

여러 인스턴스가 동시에 콜드스타트할 때, 마이그레이션이 아직 기동 경로에 남아 있으면
같은 DDL을 동시에 돌려 충돌/락 타임아웃이 난다. → "지금 당장" 4번(마이그레이션
분리)을 해두면 이 문제 자체가 사라진다.

## 실시간(같이 뛰기) 기능

베타엔 없다. 넣을 때 Cloud Run WebSocket은 궁합이 나쁘다 — 요청 하나가 최대 60분에
강제 종료되고, 인스턴스마다 상태가 안 공유되며(→ Redis 등 별도 필요), 그러면
FastAPI가 stateful이 되어 Cloud Run의 stateless 전제가 깨진다. → 이미 있는
**Supabase Realtime**으로 넘기면 세 문제가 통째로 사라진다.

## 비용 트레이드오프

`min-instances=1`은 콜드스타트를 없애지만 **트래픽이 0일 때도 상시 1개가 떠 있어
과금**된다. 베타 동안은 첫 요청 지연 제거 > 비용이라 켜두지만, 트래픽 패턴이 보이면
`min-instances=0`(콜드스타트 감수, 비용 절감)과 저울질한다. 우리 의존성은 가벼워서
(pandas 등 없음) 콜드스타트 지연 자체는 크지 않다.
