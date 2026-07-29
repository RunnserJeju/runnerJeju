# 아키텍처

## 전체 구성

```
Flutter 앱  ──►  FastAPI  ──►  PostGIS
                    │
                    └──►  (예정) 검증 서버
```

클라이언트는 **항상 FastAPI에만 요청한다.** 검증 서버가 분리되더라도 앱이 그 주소를 알 필요가 없도록 FastAPI가 앞단을 유지한다.

## 클라이언트 계층 구조

`frontend/app/lib` 아래는 아래 4계층으로 나눈다. 위 계층은 아래 계층만 알고, 건너뛰지 않는다.

| 계층 | 위치 | 책임 | 알지 못하는 것 |
| --- | --- | --- | --- |
| UI | `screens/`, `widgets/` | 화면 구성, 사용자 입력 | Dio, 엔드포인트 경로 |
| 비즈니스 로직 | `services/` | 상태 관리, 오류 문구 변환, 폴링 | HTTP 상태 코드, JSON 모양 |
| API | `api/` | 엔드포인트 1개당 메서드 1개, JSON ↔ 모델 | 화면, 위젯 |
| Transport | `network/` | HTTP 통신 자체 | 엔드포인트, 응답 의미 |

`models/`는 순수 도메인 타입이라 어느 계층에서든 쓴다. 특히 `GeoPoint`는 카카오맵 SDK의 `LatLng`와 별개로 두었고, 변환은 `widgets/run_map_view.dart` 안에서만 일어난다. 지도 SDK를 바꿔야 할 때 손댈 파일이 그 하나로 묶인다.

전역 인스턴스는 `services/service_locator.dart`의 `Services.instance` 하나로 모았다. 상태관리 패키지를 도입하기 전까지의 최소 DI다.

## 경로 검증 (verification)

### 결정

러닝 경로가 코스대로 달린 것인지 판정하는 GPX 비교 연산은 **CPU를 오래 점유한다.** 이 연산이 FastAPI 워커를 붙잡으면 그동안 다른 모든 API 요청이 함께 느려진다. 그래서 검증 연산은 **별도의 검증 서버로 분리한다.**

다만 지금 단계에서는 서버를 실제로 분리하지 않는다. **FastAPI 안에서 검증 로직까지 처리하고**, 분리는 부하가 실제로 문제가 될 때 한다.

### 이유

서버를 지금 나누면 배포 대상과 서비스 간 통신·장애 처리가 먼저 늘어나는데, 아직 검증 로직 자체가 없어서 얼마나 무거운지도 모른다. 반대로 **분리를 나중에 하더라도 클라이언트가 바뀌지 않게 만드는 것은 지금 해둘 수 있다.** 비용이 거의 들지 않으므로 그 부분만 미리 처리했다.

### 클라이언트가 미리 맞춰둔 것

검증 API는 처음부터 **비동기 계약**으로 설계했다.

```
POST /runs/{run_id}/verification   { course_id }   →  RunVerification
GET  /verifications/{id}                           →  RunVerification
```

`RunVerification.status`는 `pending` / `inProgress` / `matched` / `mismatched` / `failed` 5가지다. 지금은 FastAPI가 동기로 계산해서 POST 응답이 곧바로 `matched` 같은 terminal 상태로 오지만, 클라이언트는 **pending이 올 수 있다고 가정하고 짜여 있다** (`services/verification_service.dart`의 `awaitResult`가 2초 간격으로 폴링, 60초에 포기).

그래서 검증 서버를 분리해 POST가 `pending`을 반환하기 시작해도 **클라이언트는 한 줄도 바뀌지 않는다.** 폴링 경로가 그때 처음 동작할 뿐이다. 화면(`screens/run/run_result_screen.dart`)도 5가지 상태를 모두 이미 그리고 있다.

### 분리할 때 서버가 할 일

1. FastAPI가 검증 요청을 받으면 검증 서버로 넘기고 즉시 `pending`으로 응답
2. `GET /verifications/{id}`가 검증 서버의 진행 상태를 조회해 반환
3. 앱에서 보는 엔드포인트 주소는 그대로 유지

폴링 대신 푸시로 바꾸고 싶다면 그때 `awaitResult`만 교체하면 되고, API 계약과 화면은 유지된다.

### 스탬프와의 관계

완주 스탬프는 **검증에서만 발급된다.** `POST /runs`는 기록을 저장할 뿐 검증도 스탬프 발급도 하지 않는다(응답의 `earned_stamp_id`는 항상 null이다. 필드를 남긴 건 나중에 동기 발급 경로가 생길 여지를 두기 위해서다).

스탬프 발급 경로를 검증 한 곳으로 모은 이유는, 검증이 비동기가 되어도 **"스탬프는 검증 결과로 생긴다"는 규칙이 그대로 유지되기 때문이다.** 만약 `POST /runs`에서도 스탬프를 줬다면, 검증 서버를 분리하는 순간 그 경로만 따로 고쳐야 한다.

그래서 `VerificationOut`에 `earned_stamp_id`가 있고, 앱은 검증이 `matched`로 돌아왔을 때 그 id로 스탬프를 조회해 결과 화면에 띄운다. 검증이 오래 걸려 `pending`으로 오면 스탬프는 나중에 스탬프 탭에서 확인하게 되며, 화면은 이미 "검증이 끝나면 스탬프가 발급돼요" 문구로 그 경우를 처리한다.

같은 코스를 여러 번 완주해도 스탬프는 하나만 유지된다 (`stamps` 테이블의 `(user_id, course_id)` unique 제약).

## 서버 구조

```
server/
  app/
    main.py           앱 조립, 라우터 등록, 스키마 가드
    db.py             엔진 / 세션 / Base
    models.py         SQLAlchemy ORM (courses, runs, verifications, stamps)
    schemas.py        Pydantic — 필드명이 곧 앱과의 계약
    geo.py            위경도 계산 (순수 함수)
    gpx.py            GPX → 코스 경로 (순수 함수)
    verification.py   검증 연산 (순수 함수, 분리 대상)
    schema_guard.py   DB 리비전이 head인지 확인
    deps.py           요청 단위 의존성 (현재는 개발용 사용자 고정)
    routers/          엔드포인트
  courses/            코스 GPX 원본 + courses.yaml 명단
  tools/              운영 스크립트 (push_courses.py)
  migrations/         Alembic
  tests/
```

`schemas.py`의 필드 이름은 Flutter의 `fromJson`/`toJson` 키와 1:1이다. **한쪽만 바꾸면 앱이 조용히 깨진다.** 특히 `VerificationStatus`는 Dart enum 이름을 그대로 쓰기 때문에 `inProgress`가 camelCase다.

`verification.py`는 DB 세션도 FastAPI도 ORM도 import하지 않는다. 검증 서버로 분리할 때 **이 파일을 그대로 옮기면 되도록** 순수 함수만 담았다.

### 스키마 관리

스키마는 **Alembic만** 관리한다. 기동 시 `Base.metadata.create_all`을 부르던 코드는 제거했다 — 컬럼 변경을 반영하지 못해서, 모델을 고쳐도 DB는 그대로인 채 서버가 조용히 뜨는 상태를 만들기 때문이다.

마이그레이션 누락은 두 겹으로 막는다.

1. 도커 엔트리포인트(`server/docker-entrypoint.sh`)가 uvicorn보다 **먼저** `alembic upgrade head`를 실행한다
2. 그 경로를 우회해도, 앱이 기동 시 DB 리비전이 head인지 확인하고 아니면 기동을 거부한다 (`app/schema_guard.py`)

`migrations/env.py`의 `include_object`는 **PostGIS가 만든 테이블을 autogenerate 대상에서 제외한다.** DB 이미지가 PostGIS라 `topology`, `layer`, `spatial_ref_sys` 등이 함께 들어 있는데, 걸러내지 않으면 autogenerate가 이들을 "메타데이터에 없는 테이블"로 보고 전부 DROP하는 마이그레이션을 만들어낸다.

### 아직 정리되지 않은 것

- **인증이 없다.** 클라이언트에 로그인 화면이 없어서 "내 기록"의 주체를 특정할 수 없다. 지금은 `deps.py`의 `DEV_USER_ID` 한 명이 모든 요청을 보낸 것으로 취급한다. 인증을 붙일 때 `current_user_id`만 교체하면 라우터는 그대로 둘 수 있다. **코스 등록 API(`PUT /courses/gpx`)도 그때 admin 전용으로 막아야 한다** — 지금은 누구나 코스를 등록/수정할 수 있다.
- **경로를 PostGIS가 아니라 JSONB에 저장한다.** 지금 앱이 쓰는 API에는 공간 질의가 없고, 경로는 그리기와 순서 비교에만 쓰여서 JSONB로 충분하다. "내 주변 코스 검색" 같은 질의가 실제로 필요해지면 그때 `geography(LineString, 4326)` 컬럼을 추가하는 편이 낫다.

## 코스 데이터 파이프라인

공식 코스는 관리자가 경로 플래너에서 **그려서** 내보낸 GPX로 만든다. 누가 달린 기록이 아니다. 실제 파일(사계해안도로 6.2km)을 보면 그 성격이 드러난다.

```
trkpt 207개 · <time> 없음 · 점 간격 평균 30m (최장 252m)
계산 거리 6232.6m · 시작↔끝 10.5m(순환) · 고도 2.5~6.8m
```

### 흐름

```
server/courses/*.gpx  +  courses.yaml
        │
        │  tools/push_courses.py
        ▼
  PUT /courses/gpx  (multipart)
        │  app/gpx.py 파싱 → 거리·고도·순환 계산
        ▼
     courses 테이블 (path JSONB)
        │
        ▼
   앱이 GET /courses 로 받아 지도에 폴리라인으로 그림
```

**스크립트가 DB에 직접 쓰지 않고 API를 거치는 이유**는, 코스가 DB로 들어가는 경로를 하나로 유지하면 검증 규칙(GPX 파싱, 제주 경계 확인, 거리 계산)이 한 곳에만 있으면 되기 때문이다. 스크립트가 DB에 직접 쓰면 그 규칙이 두 벌이 되고 언젠가 서로 어긋난다.

**GPX에 없는 정보만 `courses.yaml`에 적는다.** 지역, 난이도, 소개글이 그것이다. 거리·고도·순환 여부는 폼으로 받지 않고 GPX에서 계산한다 — 파일과 어긋난 값이 들어오는 경로를 아예 만들지 않기 위해서다.

### slug

`courses.slug`는 코스의 영구 식별자이고, 재업로드 시 같은 코스를 알아보는 기준이다.

- **id(uuid)로는 안 된다** — 업로드하는 쪽이 uuid를 모른다
- **이름으로도 안 된다** — 코스명이 바뀌면 같은 코스가 둘로 갈라진다

재업로드가 **갱신**이어야 하는 이유는 스탬프 때문이다. `stamps`는 `course_id`를 FK로 잡고 `(user_id, course_id)` 유니크를 쓰므로, 코스를 지웠다 다시 만들면 이미 발급된 완주 스탬프가 고아가 된다. 그래서 등록 API는 POST가 아니라 **멱등한 PUT**이다.

### 다운샘플링을 하지 않는 이유

GPS 기록이라면 초당 1점이라 수천 점이 쌓이고 Douglas-Peucker 같은 단순화가 필요하다. 하지만 이 데이터는 **그려진 경로**라 6.2km에 207점(중복 제거 후 185점)뿐이다. 줄일 것이 없다.

문제는 오히려 반대다. **점 간격이 성기다** — 100m를 넘는 구간이 15개, 최장 252m다. 그래서 "러너가 코스 위에 있는가"를 코스 *꼭짓점*과의 거리로 재면 안 된다. 252m 직선 구간 한가운데를 정확히 달린 사람이 126m 벗어난 것으로 잡힌다. `geo.distance_to_segment_meters`가 꼭짓점이 아니라 **선분**까지의 거리를 재는 이유다.

(현재 `verification.py`의 `coverage_ratio`는 아직 점-대-점으로 계산한다. 검증 로직을 실제로 다듬을 때 선분 기준으로 옮겨야 한다.)

### 고도

`elevation_gain_meters`는 잔떨림을 걸러내려고 3m 임계값을 쓴다(`geo.elevation_gain_meters`). 사계해안도로는 이 계산으로 3m가 나오는데, 해안도로라 실제로 평탄한 것이 맞다. 다만 이 정도 값은 측정 노이즈와 구분되지 않으므로 **UI에서 의미를 부여하지 않는 편이 낫다.** 한라산 쪽 코스가 들어오면 그때 다시 볼 값이다.

## 지도

카카오맵은 `kakao_map_plugin`(WebView 기반)을 쓴다. JavaScript 앱 키가 필요하고, `--dart-define=KAKAO_MAP_KEY=...`로 주입한다 (`config/app_config.dart`).

키 없이 빌드해도 **앱은 뜬다.** `RunMapView`가 지도 대신 안내 화면으로 대체되므로, 지도와 무관한 화면은 키 없이도 개발할 수 있다.

### 웹은 지원하지 않는다

`kakao_map_plugin`은 `webview_flutter` 래퍼이고, 패키지의 `plugin.platforms`에 android/ios만 등록되어 있다(`kakao_map_plugin_web.dart`는 `getPlatformVersion` 스텁뿐이다). `KakaoMap` 위젯은 무조건 `WebViewController`를 만드는데 `webview_flutter`에는 웹 구현체가 없다.

그래서 **`flutter run -d chrome`에서는 지도만 깨진다.** 브라우저는 코스 목록·스탬프 같은 지도 없는 화면을 빠르게 확인하는 용도로만 쓰고, 지도 확인은 안드로이드 에뮬레이터나 실기기에서 한다.

웹을 지원해야 한다면 `RunMapView`를 조건부 import로 쪼개고 웹용은 카카오 JS SDK를 `HtmlElementView` + `dart:js_interop`으로 직접 붙여야 한다. 나머지 화면은 `RunMapView`의 공개 API(`coursePath` / `runPath` / `currentPosition`)만 보므로 손대지 않아도 된다.

## 위치 수집

`geolocator`를 `services/location_service.dart`로 감싸서 UI가 geolocator 타입을 직접 보지 않게 했다. 러닝 중에는 `distanceFilter: 5`로 **5m 이상 움직였을 때만** 경로에 점을 추가한다. 정지 상태의 GPS 흔들림이 거리에 누적되는 것을 막기 위한 값이다.

거리 계산은 서버를 기다리지 않고 단말에서 한다 (`utils/geo_utils.dart`, Haversine). 달리는 중 실시간으로 보여줘야 하기 때문이다. **다만 이 값은 표시용이고, 완주 판정의 근거는 아니다** — 판정은 위의 검증이 담당한다.
