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

## 현재 운영 엔드포인트 맵

혼재(공개+운영)된 라우터에서 아래 6개가 운영 전용(`require_admin`).

| 현재 경로 | 이동 후 | 클라(Flutter) 호출부 |
|---|---|---|
| `PATCH /courses/{id}` | `PATCH /admin/courses/{id}` | `CourseApi.updateCourse` |
| `POST /courses/gpx` | `POST /admin/courses/gpx` | `CourseApi.uploadGpx` |
| `PUT /courses/{id}/gpx` | `PUT /admin/courses/{id}/gpx` | (아직 없음 — 운영 웹에서 구현) |
| `PUT /courses/{id}/thumbnail` | `PUT /admin/courses/{id}/thumbnail` | (아직 없음 — 운영 웹에서 구현) |
| `DELETE /courses/{id}/thumbnail` | `DELETE /admin/courses/{id}/thumbnail` | (아직 없음 — 운영 웹에서 구현) |
| `POST /banners` | `POST /admin/banners` | `BannerApi` (배너 등록) |
| `DELETE /banners/{id}` | `DELETE /admin/banners/{id}` | `BannerApi` (배너 삭제) |
| `POST /notices` | `POST /admin/notices` | `NoticeApi` (공지 등록) |
| `GET /geo/geocode` | `GET /admin/geo/geocode` | `GeoApi` — 코스 등록 화면의 주소→좌표 변환 |

공개로 남는 것(이동 없음): `GET /courses`, `GET /courses/{id}`, `GET /banners`, `GET /notices`.

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

**조회 응답 추가 필드**: `GET /courses`(목록)·`GET /courses/{id}`(상세) 모두에 `estimated_time_min: int|null`, `thumbnail_url: str|null` 포함. 앱은 반영 완료(소요시간 표시, 썸네일 카드).

**Storage 버킷**: 배너와 분리. 썸네일은 `SUPABASE_COURSE_BUCKET`(기본 `course-thumbnails`), 배너는 `SUPABASE_STORAGE_BUCKET`(기본 `banners`). **배포 전 Supabase에 `course-thumbnails` Public 버킷 생성 필요.**

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

### 3단계 — 운영 웹 프론트
- [ ] 스택 확정 (후보: Vite + React + TS + TanStack Query)
- [ ] `admin_users` / `admin_sessions` 마이그레이션 (Alembic)
- [ ] 세션 로그인 API (`POST /admin/login`, `POST /admin/logout`) + 세션 미들웨어/의존성
- [ ] 운영 화면 구현 (코스 등록/수정, 배너, 공지, geocoding)
- [ ] CORS를 어드민 도메인 기준으로 조정 (credentials 허용)

### 4단계 — 앱 운영 화면 제거
- [ ] Flutter 운영 화면·admin API 메서드 삭제
- [ ] 운영 웹으로 완전 이관 확인 후 정리

## 결정됨 — 기록 있는 코스의 경로(GPX) 수정
- **초기화 후 교체**로 결정(2026-08-30). `reset_records=true`면 완주 스탬프·검증을 hard delete, 경로 교체. 개인 러닝 기록(Run)은 유지 → 개인 히스토리 보존 + 감사 흔적
- soft delete 안 함 — `uq_stamp_user_course` 유니크가 부분 인덱스(`WHERE deleted_at IS NULL`)로 바뀌어야 하고 모든 Stamp/Verification 조회에 필터가 붙는 광범위 변경 대비, "사라진 옛 경로 완주"를 되살릴 실익이 약함. 되돌리기 안전장치가 필요해지면 개별 soft delete보다 리셋 이벤트(누가/언제/몇 건) admin 액션 로그가 더 싸고 명확 — 필요 시 추가
- Run은 course_id를 유지한 채 완주 스탬프만 사라진 "달렸지만 미완주" 정상 상태가 됨

## 보류 / 검토 필요
- CSRF — 쿠키 세션은 CSRF 노출. 어드민 웹이 다른 오리진이면 토큰 방식(쿠키+헤더) 필요. 구현 시 결정
- 크로스도메인 쿠키 — 어드민 웹과 API가 다른 도메인이면 `SameSite=None; Secure` + CORS `allowCredentials` 필요. 같은 서브도메인으로 두면 단순. 배포 도메인 확정 후 결정
- 세션 저장소 — Postgres 테이블로 시작(Redis 불필요). 트래픽·인스턴스 늘면 재검토
- 웹 프론트 스택 — React/Vite 유력하나 미확정
- geocoding 툴(`/geo/geocode`) — 앱의 `GeoApi`가 코스 등록 화면에서 호출함(확인됨). `/admin`으로 이동, 2단계에서 `GeoApi` 경로도 갱신
