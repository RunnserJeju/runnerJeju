# 운영자 웹 분리

운영자 전용 기능을 별도 웹 프론트로 빼고, 서버는 FastAPI 하나를 유지한 채 운영 API를 `/admin/*`로 모은다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 백엔드 | FastAPI 하나 유지 (Spring 분리 안 함) | 두 서비스가 한 DB를 공유하면 스키마 동기화가 상시 수작업 → 휴먼 에러. 얻는 건 "별도 배포"뿐이라 대가 대비 손해 |
| 서버 구조 | 운영 API를 `app/admin/` 서브패키지로 모으고 `/admin` prefix + 라우터레벨 `require_admin` | 공개/운영 코드가 한 파일에 섞여 경계가 안 보이는 게 실제 문제. 가드를 구조로 강제하면 새 운영 API에서 빠뜨릴 수 없음 |
| 운영 프론트 | 별도 웹 앱 (앱과 분리) | 운영은 데이터 테이블·폼 중심. Flutter의 운영 화면은 최종적으로 제거 |
| 웹 인증 | 자체 세션 방식 (소셜로그인 X) | 계정 소수. 서버측 세션 저장 → 즉시 무효화(강제 로그아웃) 가능. 앱의 JWT와 완전 분리 |
| 전환 방식 | "이사" — 앱 클라도 `/admin/*`로 먼저 맞춰 계속 돌리다, 웹 완성 후 앱 운영 화면 제거 | 무중단. 서버 리팩터와 웹 개발 타임라인을 분리 |

## 운영 엔드포인트 맵

이동은 끝났다(1단계). **호출자는 현재 없다** — 앱에서 걷어냈고(3단계) 운영 웹은
아직 없다. 아래가 운영 웹이 붙여야 할 전체 목록이다.

| 엔드포인트 | 용도 |
|---|---|
| `GET /admin/courses` | 코스 목록 (운영 웹용 — 공개 GET은 앱 JWT 필요) |
| `GET /admin/courses/{id}` | 코스 상세 (경로 포함) |
| `POST /admin/courses/gpx` | 코스 등록 (multipart, GPX + 메타데이터) |
| `PATCH /admin/courses/{id}` | 코스 메타데이터 수정 |
| `PUT /admin/courses/{id}/gpx` | 경로 교체 (기록 있으면 409 → `reset_records=true`) |
| `PUT /admin/courses/{id}/thumbnail` | 썸네일 설정/교체 |
| `DELETE /admin/courses/{id}/thumbnail` | 썸네일 제거 |
| `PUT /admin/courses/{id}/stamp-image` | 완주 스탬프 도안 설정/교체 |
| `DELETE /admin/courses/{id}/stamp-image` | 스탬프 도안 제거 |
| `POST /admin/banners` | 배너 등록 |
| `DELETE /admin/banners/{id}` | 배너 삭제 |
| `GET /admin/notices` | 공지 전체 목록 (예약·만료 포함 — 관리용) |
| `POST /admin/notices` | 공지 등록 (category + 노출 기간) |
| `PATCH /admin/notices/{id}` | 공지 수정 (전체 교체) |
| `DELETE /admin/notices/{id}` | 공지 삭제 |
| `GET /admin/missions` | 미션 전체 목록 (비활성·만료 포함) |
| `GET /admin/missions/{id}` | 미션 상세 |
| `POST /admin/missions` | 미션 등록 |
| `PATCH /admin/missions/{id}` | 미션 수정 (전체 교체) |
| `DELETE /admin/missions/{id}` | 미션 삭제 |
| `GET /admin/geo/geocode` | 주소→좌표 변환 (코스 등록 화면용) |

공개로 남는 것: `GET /courses`, `GET /courses/{id}`, `GET /banners`, `GET /notices`.

## 코스 관리 필드·썸네일 (백엔드, 2026-08-30)

운영 웹 코스 등록/수정 화면이 참고할 스펙. 서버 구현·테스트 완료(마이그레이션 `0011`).

**등록 `POST /courses/gpx`** (multipart) — 폼 필드: `file`(GPX), `distance_km`(≥1), `difficulty`(1~3), `address`, `name?`, `tags?`(쉼표구분), `parkings?`/`restrooms?`(좌표 포함 JSON 배열), `description?`, **`estimated_time_min?`**(예상 소요시간 분, ≥1). 썸네일은 여기서 안 받는다 — 등록 직후 아래 썸네일 엔드포인트로 올린다.

**수정 `PATCH /courses/{id}`** (JSON) — `name`, `distance_km`, `difficulty`, `address`, `tags?`, `description?`, **`estimated_time_min?`**, `parkings`/`restrooms`. path·썸네일은 안 건드린다.

**경로 교체 `PUT /courses/{id}/gpx`** (multipart, `file`: GPX, `reset_records?`: bool) — path만 새 GPX로 갈아끼운다. 메타데이터·썸네일은 안 건드린다. 응답은 `CourseSummary`.
- 이 코스로 달린 기록(러닝·검증·완주 스탬프)이 있는데 `reset_records`가 없으면(false) → **409**. 클라가 "완주 기록이 초기화됩니다" 경고를 띄우고 확인받으라는 신호.
- `reset_records=true` → **완주 스탬프·검증을 hard delete로 초기화**한 뒤 경로 교체. **개인 러닝 기록(Run)은 유지**(개인 활동 히스토리 + 감사 흔적). 완주 수는 0으로 리셋됨.
- 기록이 없으면 플래그와 무관하게 그냥 교체.
- 파일 검증이 초기화보다 먼저라, GPX가 잘못됐으면 아무것도 안 지우고 422.
- UI 흐름: 수정 시도 → (409면) 경고 다이얼로그 → 확인 → `reset_records=true`로 재요청.

**썸네일 (전용 리소스)** — 이미지 파일 처리를 등록/수정 폼과 분리:
- `PUT /courses/{id}/thumbnail` (multipart, `file`: jpg/png/webp, ≤8MB) — 설정/교체. 교체 시 옛 오브젝트 삭제. 응답은 `CourseSummary`.
- `DELETE /courses/{id}/thumbnail` — `thumbnail_url`을 null로 + Storage 파일 삭제. 이미 없으면 no-op.
- 등록도 이 엔드포인트로 올린다 → "처음 설정"과 "교체"가 같은 코드.

**조회 응답 추가 필드**: `GET /courses`(목록)·`GET /courses/{id}`(상세) 모두에 `estimated_time_min: int|null`, `thumbnail_url: str|null` 포함.

앱 표시 완료 (2026-08-31) — 홈 추천 카드, 코스 탐색 목록·프로필 찜 목록
(`CourseCard` 좌측 100px), 코스 바텀시트(16:9). 공통 위젯
`widgets/course_thumbnail.dart`가 `cached_network_image`로 그리고, URL이 없거나
실패해도 같은 크기의 플레이스홀더를 그려 카드 높이가 흔들리지 않는다.
바텀시트에서는 **시작 버튼 아래**에 둔다 — 접힘 높이(`_collapsedSize`)가 시작
버튼까지만 보이도록 맞춰져 있어서 그 위에 끼우면 약속이 깨진다.

**Storage 버킷**: 배너와 분리. 썸네일은 `SUPABASE_COURSE_BUCKET`(기본 `course-thumbnails`), 배너는 `SUPABASE_STORAGE_BUCKET`(기본 `banners`), 스탬프 도안은 `SUPABASE_STAMP_BUCKET`(기본 `course-stamps`).

## 스탬프 도안 (백엔드, 2026-09-02)

코스 완주 시 주는 스탬프 도안. 마이그레이션 `0012`. 스탬프는 코스에 1:1 종속이라
도안을 코스에 붙였다(별도 테이블 없음).

- **`courses.stamp_image_url`** 신규 컬럼. `GET /admin/courses`·`GET /courses` 응답에 포함.
- 설정: `PUT /admin/courses/{id}/stamp-image` (multipart, `file`: jpg/png/webp, ≤8MB, 전용 버킷 `course-stamps`). 교체 시 옛 오브젝트 삭제. 응답 `CourseSummary`.
- 제거: `DELETE /admin/courses/{id}/stamp-image` → null + Storage 삭제. 없으면 no-op.
- **라이브 참조**: 발급된 스탬프(`GET /stamps`)의 `image_url`은 저장값이 아니라 `courses.stamp_image_url`에서 조회 시 가져온다 → 운영자가 나중에 도안을 넣거나 바꿔도 **이미 완주한 사람까지 반영**. (그래서 죽은 컬럼 `stamps.image_url`은 0012에서 제거)
- 앱: 스탬프 탭 앨범이 획득 칸은 도안, 미획득 칸은 회색 목표 도안으로 그린다.
- 배포 전 Supabase에 `course-stamps` Public 버킷 생성 필요(썸네일 `course-thumbnails`와 같은 방식).

## 공지사항 관리 (백엔드, 2026-09-02)

공지 = `title, body, category, starts_at?, ends_at?, created_at`. 마이그레이션 `0013`.

- **category** — 고정 5종(운영자가 추가 못 함, "기타(etc)"가 그 외 흡수): `app_guide`(앱 이용 안내) · `new_course`(신규 코스) · `event`(이벤트) · `maintenance`(점검) · `etc`(기타). 영문 키 저장 → 앱이 라벨·칩 색 매핑. 등록 시 **필수**.
- **노출 기간** `starts_at`/`ends_at` — 둘 다 선택(생략=제한 없음). `starts_at=null` 즉시부터, `ends_at=null` 무기한. 검증: `ends_at ≥ starts_at`(어기면 422).
- **`GET /notices`(공개, 앱)** — 지금 노출 중인 것만(예약·만료 제외). 앱 JWT 필요.
- **`GET /admin/notices`(운영)** — 전체(예약·만료 포함). 관리 화면은 이걸 쓴다.
- **`POST` / `PATCH`(전체 교체) / `DELETE /admin/notices/{id}`** — 작성·수정·삭제.

운영 웹 폼: 제목·본문·카테고리(드롭다운 5종)·노출 시작/종료(선택). 목록은 `GET /admin/notices`로 예약·만료까지 보여주고 상태 뱃지를 붙이면 좋다.

## 미션 관리 (백엔드, 2026-09-02)

이벤트 미션 = `title, body, condition, reward, starts_at?, ends_at?, is_active, sort_order`. 마이그레이션 `0014`. **운영자 정의 API만** — 달성 자동 판정·유저 참여/진행·리워드 지급은 아직 없다(런타임은 나중).

- **condition / reward** — **자유 텍스트**(예: "제주 코스 3개 완주" / "굿즈 + 포인트 500"). 자유도를 낮추려 타입 enum이 아니라 서술형으로 뒀다. 등록 시 **필수**. 자동 판정이 필요해지면 그때 condition을 타입+목표값으로 구조화한다.
- **참여 기간** `starts_at`/`ends_at` — 둘 다 선택(생략=제한 없음). 검증 `ends_at ≥ starts_at`(422).
- **is_active / sort_order** — 노출 on/off(기간과 별개)와 정렬. 배너와 같은 방식.
- **CRUD**: `GET /admin/missions`(전체), `GET /admin/missions/{id}`, `POST`, `PATCH`(전체 교체), `DELETE`.
- 공개 `GET /missions`(앱)는 아직 없음 — 프론트 붙일 때 추가(공지처럼 노출 필터 얹으면 됨).

운영 웹 폼: 제목·내용·달성 조건(텍스트)·리워드(텍스트)·참여 시작/종료(선택)·노출 여부·정렬.

### 미션 — 다음 단계 & 결정 필요 (요구사항 확정 후 이어서)

지금은 **1차 틀 = 운영자 "정의" API(Layer 1)만** 있다. 앱 노출·참여·진행·달성·리워드는 전부 미구현이고, **요구사항이 정해져야 다음 API가 결정된다.**

**전체 레이어**
| 레이어 | 내용 | 상태 |
|---|---|---|
| L1 정의 (운영자) | 미션 CRUD (`/admin/missions`) | ✅ 완료 |
| L2 노출 (앱) | `GET /missions` — 유저가 미션 목록/상세 조회 | ❌ 미구현 (어느 방향이든 필요) |
| L3 참여·진행·달성·리워드 | 유저 참여, 진행률, 달성 판정, 리워드 지급 | ❌ 미구현 (방향 미정) |

**⚠️ 핵심 제약**: 현재 `condition`/`reward`는 **자유 텍스트**라 **서버가 달성을 자동 판정할 수 없다**("코스 3개 완주"가 글자일 뿐). L3 방향이 여기서 갈린다.

**L3 방향 3안 (+ 각각 추가될 API)**
- **A. 전시형(안내만)** — 참여/진행 추적 없음, 리워드는 수동/오프라인. 추가: `GET /missions`(공개)뿐. condition/reward 텍스트 그대로 표시. → 가장 단순, 텍스트 모델 유지.
- **B. 수동 달성** — 유저 참여 신청 → 운영자가 달성 확인 → 리워드 지급. 추가: `mission_participations` 테이블 + `POST /missions/{id}/join` · `GET /me/missions`(내 참여/상태) · `POST /admin/missions/{id}/participants/{user}/complete`(달성 마킹) · `GET /me/rewards`. → 텍스트 조건 그대로 가능.
- **C. 자동 판정** — 서버가 스탬프/러닝 데이터로 진행률 자동 계산·달성·지급. 추가: **condition 구조화(자유텍스트 → 타입+목표값, 스키마 변경 필요)** + 진행률 엔진 + `GET /me/missions/{id}/progress` + 자동 지급. → 가장 강력하나 모델 재작업.

**유저(기획)가 정해야 할 것 — 요구사항 체크리스트**
- [ ] L3 방향: A / B / C 중 무엇?
- [ ] 참여 방식: 자동 집계(기간 내 활동이 자동 반영) vs 명시적 참여(참여 버튼)?
- [ ] 달성 조건 종류: 어떤 조건을 지원? (특정 코스 완주 / N개 완주 / 누적 거리 / 러닝 횟수 / 빙고 …) — **C면 이게 곧 condition 타입 enum**이 된다.
- [ ] 리워드 종류·지급: 포인트 / 배지 / 실물 쿠폰 …? 지급을 앱 안에서 처리? 오프라인?
- [ ] 반복/동시성: 한 유저가 여러 미션 동시 참여 가능? 같은 미션 반복 달성 가능?
- [ ] 미션 배너 이미지 필요 여부 (필요 시 썸네일/스탬프와 같은 업로드 패턴으로 `image_url` + 전용 엔드포인트 추가)

**연관 메모 — 빙고**: 이전 논의에서 "스탬프를 격자에 모아 빙고 완성 시 상품" 아이디어가 있었다. 빙고는 사실상 **미션의 한 구체 형태**(달성 조건 = 빙고 라인/블랙아웃, 리워드 = 상품)일 수 있다. 미션 요구사항을 정할 때 빙고를 별도 기능으로 갈지 미션 condition 타입 중 하나로 흡수할지 함께 결정하면 좋다. 빙고는 스탬프(코스 완주)에서 파생되므로, 스탬프 도안 작업(0012)과 이어진다.

**현재 모델을 바꿔야 하는 경우**: C(자동 판정)를 택하면 `missions.condition`(String) 하나로는 부족하다 — `condition_type`(enum) + `condition_config`(JSONB, 예: `{course_ids:[...]}` / `{count:3}` / `{distance_km:50}`)로 재설계가 필요하다. A/B면 지금 텍스트 모델 그대로 간다.

`course-thumbnails` Public 버킷 **생성 완료 (2026-08-31, 개발·운영 양쪽)**. 서버
제약과 같은 값으로 맞춰 뒀다 — `public=true`, `file_size_limit=8MB`,
`allowed_mime_types=[image/jpeg, image/png, image/webp]`
(`admin/courses.py`의 `MAX_THUMBNAIL_BYTES`·`_ALLOWED_IMAGE_TYPES`와 동일).
개발 버킷에 업로드→public URL 조회→삭제까지 확인했다.

> `cloudbuild.yaml`은 `SUPABASE_COURSE_BUCKET`을 넘기지 않는다 — 기본값이 곧
> 버킷 이름이라 그대로 동작한다. 버킷 이름을 바꾸려면 그때 환경변수를 추가한다.

## 목표 서버 구조

```
server/app/
  routers/            # 공개(앱) API 전용 — 사실상 read-only
    courses.py        # GET 목록/상세만
    banners.py        # GET 목록만
    notices.py        # GET 목록만
    auth.py runs.py stamps.py verifications.py
  admin/              # 운영자 전용
    __init__.py       # admin_router = APIRouter(prefix="/admin",
                      #   dependencies=[Depends(require_admin)])
    courses.py        # PATCH, POST /gpx
    banners.py        # POST, DELETE
    notices.py        # POST
    geo.py            # GET /geocode
```

`main.py`는 공개 라우터들 + `admin_router` 하나를 include.

## 웹 인증 (자체 세션)

- 로그인 수단: 기존 User는 소셜로그인뿐(비밀번호 없음) → 운영자용 `admin_users`(아이디 + BCrypt 해시) 테이블 신설
- 세션: opaque session_id를 HttpOnly·Secure·SameSite 쿠키로. 서버측 `admin_sessions` 테이블에서 조회 → row 삭제로 즉시 무효화
- 앱의 JWT 흐름과 독립 (공유 시크릿·role 클레임 문제 없음)

## 계획 (단계)

### 1단계 — 서버 `/admin/*` 리팩터 (로직 변경 없음) ✅
- [x] `app/admin/` 서브패키지 생성, `admin_router` prefix + 라우터레벨 `require_admin`
- [x] 운영 엔드포인트 6개를 각 도메인 파일에서 `admin/`로 이동
- [x] 이동한 엔드포인트에서 개별 `Depends(require_admin)` 제거 (부모가 강제) — id가 필요한 곳은 `current_user_id`로 대체
- [x] `routers/` 라우터는 공개 GET만 남김 (`routers/geo.py`는 전체가 운영이라 삭제)
- [x] `main.py`에 `admin_router` include
- [x] 테스트 143개 통과 (함수 직접 호출 방식이라 옮긴 함수의 import 경로 갱신)

> 메모: courses 공유 헬퍼(`_to_summary`·`_completed_counts`·`_my_completed_course_ids`·`create_course_from_gpx_bytes`)는 tools/push_courses.py와 테스트가 `app.routers.courses`에서 import하므로 그 자리에 두고, `app/admin/courses.py`가 재사용(import)한다.

### 2단계 — 앱 클라 경로 맞춤 (이사, 무중단 유지) ✅
- [x] `CourseApi.updateCourse` / `uploadGpx` 경로에 `/admin` 접두
- [x] `BannerApi` 등록·삭제 경로 `/admin` 접두
- [x] `NoticeApi` 등록 경로 `/admin` 접두
- [x] `GeoApi` geocode 경로 `/admin` 접두
- [x] `flutter analyze` 통과 + 서버 라우팅 런타임 확인 (admin 401·옛경로 405/404·공개 401)

> 검증: 클라 6개 admin 경로 ↔ 서버 6개 `/admin/*` OpenAPI 경로 정확히 일치. 앱 실기기 E2E(관리자 로그인 후 실제 등록)는 에뮬레이터·관리자 계정 필요라 미실행.

### 3단계 — 앱 운영 화면 제거 ✅ (2026-08-31)

**순서를 4단계와 바꿨다.** 원래 계획은 "웹 완성 후 앱 제거"였는데, 앱 새 빌드를
뽑기 전에 admin 코드를 걷어내는 게 우선이라 먼저 진행했다. 웹 완성 전까지 코스
등록은 `server/tools/push_courses.py`로 한다 — 이 스크립트는 HTTP API가 아니라
DB에 직접 쓰므로 앱·웹과 무관하게 동작한다.

- [x] `AdminOnly` 5곳 제거 (배너 등록·공지 작성·GPX 등록·코스 수정 2곳)
- [x] 화면 삭제 — `gpx_upload_screen`, `banner_create_screen`, `notice_create_screen`
- [x] API·서비스 메서드 삭제 — `CourseApi.uploadGpx`/`updateCourse`,
      `BannerApi` 등록·삭제, `NoticeApi.createNotice`, `GeoApi`/`GeoService` 통째
- [x] `widgets/admin_only.dart`, `User.isAdmin` 삭제
- [x] 시뮬레이션 노출 조건을 `AdminOnly` → `kDebugMode`로 전환.
      **릴리스 빌드에서 가짜 위치로 완주 스탬프를 딸 수 있던 구멍이 닫혔다.**
- [x] `flutter analyze` 무경고(기존 pubspec asset 경고 1건 제외), 테스트 41개 통과

앱이 호출하는 엔드포인트에 `/admin/*`이 하나도 남지 않았다.

> **서버는 건드리지 않았다.** `/admin/*` 엔드포인트와 JWT `require_admin`을 그대로
> 뒀다. 지금은 호출자가 없을 뿐이고, 4단계에서 세션 인증으로 교체하면 된다.

### 4단계 — 운영 웹 1차 (2026-09-01) ✅ — API 키 인증, 코스만

세션 인증(팀원 담당)이 준비되기 전에 코스 등록/수정부터 웹으로 쓸 수 있게,
**잠정 인증(API 키)** 으로 범위를 좁혀 배포했다. 접속: `https://<서비스 주소>/admin-ui`

인증 (잠정)
- [x] `require_admin` → `require_admin_key`(`app/deps.py`) — `X-Admin-Api-Key` 헤더를
      `ADMIN_API_KEY` 환경변수와 비교(compare_digest). JWT 경로는 제거했다
- [x] `config_guard`가 `ADMIN_API_KEY` 미설정 시 기동 거부. 로컬은 `infra/.env`,
      운영은 Secret Manager `admin-key`(cloudbuild deploy 스텝 `--set-secrets`)
- [x] admin 엔드포인트의 `current_user_id` 의존 제거 — `created_by`는 `"admin-web"`,
      응답의 `is_completed_by_me`는 False 고정(운영자에겐 무의미)
- [x] 운영 목록/상세 추가: `GET /admin/courses`, `GET /admin/courses/{id}` —
      공개 `GET /courses`는 앱 JWT가 필요해 운영 웹이 쓸 수 없다
- 세션 인증이 오면: `require_admin_key`만 세션 검사로 교체하면 된다. 프론트는
  API 키 입력칸 → 로그인 화면으로 바꾸고 fetch 헤더 한 곳만 수정

프론트 (`frontend/admin/`)
- [x] Vite + React + TS + HashRouter. **의도적으로 단순화** — TanStack Query·
      RHF·zod·Mantine·카카오맵 SDK는 쓰지 않았다(폼 3개에 과하다). 필요해지면 도입
- [x] 화면: 코스 목록 → 등록(GPX·메타·주차/화장실 좌표확인·썸네일) →
      수정(메타 PATCH·경로교체 409 확인 흐름·썸네일 교체/삭제)
- [x] API 키는 상단 입력칸 → localStorage → 매 요청 `X-Admin-Api-Key` 헤더
- 배너·공지 화면은 아직 없다(엔드포인트는 준비됨) — 2차에서

배포 (동일 오리진)
- [x] FastAPI가 `/admin-ui`에서 정적 서빙(`app/main.py`, 디렉터리 있을 때만 mount),
      `server/static/` gitignore
- [x] `cloudbuild.yaml` `admin-build` 스텝(node:22-slim, npm ci → build →
      `server/static/admin` 복사) — 테스트 스텝 다음, 이미지 빌드 전
- [x] Vite `base: '/admin-ui/'`, 개발 프록시 `/admin` → `localhost:8000`
- 개발: `cd frontend/admin && npm run dev` (서버는 8000에 따로)

남은 것 (2차)
- [ ] 세션 인증으로 교체 (`admin_users`/`admin_sessions`, bcrypt, 로그인 API — 팀원)
- [ ] 배너·공지 화면
- [ ] 목록 페이징·검색 (코스가 수십 개 수준이라 아직 불필요)

## 결정됨 — 기록 있는 코스의 경로(GPX) 수정
- **초기화 후 교체**로 결정(2026-08-30). `reset_records=true`면 완주 스탬프·검증을 hard delete, 경로 교체. 개인 러닝 기록(Run)은 유지 → 개인 히스토리 보존 + 감사 흔적
- soft delete 안 함 — `uq_stamp_user_course` 유니크가 부분 인덱스(`WHERE deleted_at IS NULL`)로 바뀌어야 하고 모든 Stamp/Verification 조회에 필터가 붙는 광범위 변경 대비, "사라진 옛 경로 완주"를 되살릴 실익이 약함. 되돌리기 안전장치가 필요해지면 개별 soft delete보다 리셋 이벤트(누가/언제/몇 건) admin 액션 로그가 더 싸고 명확 — 필요 시 추가
- Run은 course_id를 유지한 채 완주 스탬프만 사라진 "달렸지만 미완주" 정상 상태가 됨

## 결정됨 — 오리진 배치 (2026-08-31)

**운영 웹을 API와 같은 오리진에 둔다.** FastAPI가 `/admin-ui`에서 빌드된 정적
파일을 서빙하고, 그 페이지가 `/admin/*`을 호출한다.

이유는 인증 복잡도다. 다른 오리진이면 CORS `allow_credentials`(와일드카드 금지),
쿠키 `SameSite=None; Secure`, CSRF를 전부 직접 감당해야 한다. 같은 오리진이면
그게 다 사라지고 `SameSite=Lax`로 충분하다(CSRF 토큰은 여전히 넣는다).

대가는 배포 결합 — 프론트만 고쳐도 API 이미지가 다시 빌드되고 리비전이 새로 뜬다.
무중단이라 실질 영향은 없다.

나중에 배포를 분리하고 싶으면 **로드밸런서로 한 도메인에 합치는 쪽**으로 간다.
그것도 같은 오리진이라 인증 코드를 안 고친다. 별도 도메인으로 쪼개는 선택만
피하면 된다.

## 보류 / 검토 필요
- CSRF — `SameSite=Lax`로도 완전히 없어지진 않는다. 토큰 방식(쿠키+헤더) 필요
- 세션 저장소 — Postgres 테이블로 시작(Redis 불필요). 트래픽·인스턴스 늘면 재검토
- `User.role` — 운영자가 `admin_users`로 분리되면 갈 곳이 없다. 컬럼 유지 여부 미정
  (앱에서는 이미 `isAdmin`을 걷어냈다)
- geocoding 툴(`/geo/geocode`) — 앱의 `GeoApi`가 코스 등록 화면에서 호출함(확인됨). `/admin`으로 이동, 2단계에서 `GeoApi` 경로도 갱신
