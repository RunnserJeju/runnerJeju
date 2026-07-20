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
server/app/
  main.py           앱 조립, 라우터 등록
  db.py             엔진 / 세션 / Base
  models.py         SQLAlchemy ORM (courses, runs, verifications, stamps)
  schemas.py        Pydantic — 필드명이 곧 앱과의 계약
  verification.py   검증 연산 (순수 함수, 분리 대상)
  deps.py           요청 단위 의존성 (현재는 개발용 사용자 고정)
  routers/          엔드포인트
```

`schemas.py`의 필드 이름은 Flutter의 `fromJson`/`toJson` 키와 1:1이다. **한쪽만 바꾸면 앱이 조용히 깨진다.** 특히 `VerificationStatus`는 Dart enum 이름을 그대로 쓰기 때문에 `inProgress`가 camelCase다.

`verification.py`는 DB 세션도 FastAPI도 ORM도 import하지 않는다. 검증 서버로 분리할 때 **이 파일을 그대로 옮기면 되도록** 순수 함수만 담았다.

### 아직 정리되지 않은 것

- **인증이 없다.** 클라이언트에 로그인 화면이 없어서 "내 기록"의 주체를 특정할 수 없다. 지금은 `deps.py`의 `DEV_USER_ID` 한 명이 모든 요청을 보낸 것으로 취급한다. 인증을 붙일 때 `current_user_id`만 교체하면 라우터는 그대로 둘 수 있다.
- **마이그레이션이 없다.** 기동 시 `Base.metadata.create_all`로 테이블을 만든다. 컬럼 변경은 반영되지 않으므로, 스키마가 굳으면 Alembic으로 옮겨야 한다.
- **경로를 PostGIS가 아니라 JSONB에 저장한다.** 지금 앱이 쓰는 API에는 공간 질의가 없고, 경로는 그리기와 순서 비교에만 쓰여서 JSONB로 충분하다. "내 주변 코스 검색" 같은 질의가 실제로 필요해지면 그때 `geography(LineString, 4326)` 컬럼을 추가하는 편이 낫다.

## 지도

카카오맵은 `kakao_map_plugin`(WebView 기반)을 쓴다. JavaScript 앱 키가 필요.

키 없이 빌드해도 **앱은 뜬다.** `RunMapView`가 지도 대신 안내 화면으로 대체되므로, 지도와 무관한 화면은 키 없이도 개발할 수 있다.  
(나중에 추가할예쩡)

## 위치 수집

`geolocator`를 `services/location_service.dart`로 감싸서 UI가 geolocator 타입을 직접 보지 않게 했다. 러닝 중에는 `distanceFilter: 5`로 **5m 이상 움직였을 때만** 경로에 점을 추가한다. 정지 상태의 GPS 흔들림이 거리에 누적되는 것을 막기 위한 값이다.

거리 계산은 서버를 기다리지 않고 단말에서 한다 (`utils/geo_utils.dart`, Haversine). 달리는 중 실시간으로 보여줘야 하기 때문이다. **다만 이 값은 표시용이고, 완주 판정의 근거는 아니다** — 판정은 위의 검증이 담당한다.
