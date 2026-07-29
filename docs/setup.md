# 환경설정

백엔드(DB + API)는 도커로 통째로 관리한다. 로컬에 파이썬이나 postgres를 따로
설치하지 않아도 된다.

## 사전 준비

- Docker Desktop

## 실행

```powershell
.\scripts\dev.ps1 up
```

이것 하나로 끝난다. 내부적으로 일어나는 일:

1. `db`(PostGIS)가 뜨고, `pg_isready`로 **쿼리를 받을 수 있는 상태**가 될 때까지 기다린다
2. `api` 컨테이너가 `alembic upgrade head`로 스키마를 최신까지 올린다
3. uvicorn이 뜬다 (`--reload`, 호스트 소스를 바인드 마운트하므로 코드 저장 시 자동 반영)

확인:

```powershell
curl http://localhost:8000/health   # {"status":"ok","db":"connected"}
```

API 문서는 http://localhost:8000/docs 에 있다.

## 스크립트 명령

| 명령 | 하는 일 |
|---|---|
| `.\scripts\dev.ps1 up` | DB + API 기동 (빌드 포함) |
| `.\scripts\dev.ps1 down` | 전부 정지 |
| `.\scripts\dev.ps1 logs` | 로그 따라가기 |
| `.\scripts\dev.ps1 restart` | API만 재시작 |
| `.\scripts\dev.ps1 rebuild` | 이미지 새로 빌드 후 재생성 (의존성 변경 시) |
| `.\scripts\dev.ps1 migrate` | 스키마를 head까지 올리기 |
| `.\scripts\dev.ps1 revision "메시지"` | 마이그레이션 자동 생성 |
| `.\scripts\dev.ps1 seed` | `server/courses/`의 GPX를 API로 업로드 |
| `.\scripts\dev.ps1 test` | pytest |
| `.\scripts\dev.ps1 psql` | DB 셸 |
| `.\scripts\dev.ps1 shell` | API 컨테이너 셸 |

## 스키마 변경

스키마는 **Alembic만** 관리한다. 예전에 쓰던 `Base.metadata.create_all`은 제거했다 —
컬럼 변경을 반영하지 못해서, 모델을 고쳐도 DB는 그대로인 채 서버가 조용히 뜨는
상태가 만들어지기 때문이다.

`models.py`를 고쳤다면:

```powershell
.\scripts\dev.ps1 revision "add course tags"
.\scripts\dev.ps1 migrate
```

`--autogenerate`가 만든 파일은 **반드시 눈으로 확인한다.** 컬럼 이름 변경을
DROP + ADD로 잡는 등 의도와 다르게 나오는 경우가 있다.

마이그레이션을 빠뜨린 채 서버가 뜨는 일은 두 겹으로 막아둔다.

- 도커 엔트리포인트가 uvicorn보다 먼저 `alembic upgrade head`를 실행한다
- 그 경로를 우회해도(로컬에서 직접 `uvicorn` 실행 등), 앱이 기동 시 DB 리비전이
  head인지 확인하고 아니면 무엇을 해야 하는지 알려주며 기동을 거부한다
  (`app/schema_guard.py`)

### 이미 `create_all`로 만든 DB가 있다면

Alembic 도입 전에 만들어진 DB는 `alembic_version` 테이블이 없어서 baseline부터
다시 실행하려다 "테이블이 이미 있다"로 실패한다. baseline을 건너뛰고 합류한다:

```powershell
.\scripts\dev.ps1 shell
alembic stamp 0001_baseline
alembic upgrade head
```

## 도커 없이 로컬에서 돌리고 싶다면

[uv](https://docs.astral.sh/uv/)가 필요하다. DB는 여전히 도커로 띄우는 편이 쉽다.

```powershell
docker compose -f infra/docker-compose.yml up -d db
cd server
uv sync
$env:DATABASE_URL = "postgresql+psycopg://runner:runner@localhost:5432/runner_jeju"
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 8000
```

`alembic upgrade head`를 빠뜨리면 위의 스키마 가드가 기동을 막는다.

## 카카오 로그인·지도 로컬 개발 (Flutter)

**로그인과 지도가 네이티브 앱 키 하나를 공유한다.** 카카오는 앱당 네이티브 앱 키를
하나만 발급하고 Android/iOS가 같은 값을 쓴다.

이 키는 dart-define으로 넘기지 않는다. 앱 바이너리에 담겨 배포되는 값이라 숨길 수 없고,
로그인 리다이렉트 스킴(`kakao<앱키>`)은 런타임 주입도 불가능해서 어차피 manifest에
리터럴로 있어야 하기 때문이다. 저장소에 박아두고 쓴다:

- `android/app/src/main/AndroidManifest.xml` — 원본
- `lib/config/app_config.dart`의 `kakaoNativeAppKey` — 위와 같은 값

**한쪽만 바꾸면 안 된다.** SDK 초기화와 리다이렉트가 서로 다른 앱을 가리키면서
로그인이 조용히 깨진다.

그래서 넘길 것은 API 서버 주소뿐이다:

```powershell
flutter run --dart-define=API_BASE_URL=http://<맥/PC의 LAN IP>:8000
```

VSCode에서 매번 치기 귀찮으면 `frontend/app/.vscode/launch.json.sample`을
`launch.json`으로 복사해서 값만 채우면 된다(이 파일은 개인 값이 들어가서 git에 안 올라간다).

### 각자 새로 세팅할 때 카카오 콘솔에 등록해야 하는 것

- **카카오맵 이용약관 동의**: 콘솔에서 카카오맵 SDK 약관에 별도로 동의해야 지도가 뜬다.
  로그인만 쓸 때는 필요 없던 단계다.
- **Android**: 본인 PC의 디버그 키 해시를 콘솔 플랫폼 설정에 추가로 등록해야 한다
  (키 해시는 PC마다 다르다 — 이미 등록된 다른 사람 키 해시로는 로그인이 안 된다).
  **Git Bash에서 실행한다** — PowerShell에는 `openssl`이 없다.
  ```bash
  keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android | openssl sha1 -binary | openssl base64
  ```
  앱이 이미 뜨는 상태라면 `KakaoMapSdk.instance.hashKey()`로 실행 중인 빌드의
  키 해시를 직접 찍어볼 수도 있다. 등록한 값과 실제 값이 어긋났을 때 원인 찾기가 빠르다.
- **iOS 서명**: `frontend/app/ios/Flutter/Signing.xcconfig.sample`을
  `Signing.xcconfig`로 복사하고 본인 Apple ID Team ID로 채운다. **Xcode의
  Signing & Capabilities 화면에서 직접 Team을 선택하지 말 것** — Xcode가 그 값을
  `project.pbxproj`에 다시 박아버려서 다른 사람 로컬 세팅과 충돌한다.
- Android SDK 36 / Xcode가 처음 세팅된 PC라면 라이선스 동의, 플랫폼 다운로드가
  추가로 필요할 수 있다(`flutter doctor`가 알려준다).
