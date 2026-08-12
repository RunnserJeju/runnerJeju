# MVP

## 목표

GPS로 러닝 기록 → 공식 코스와 유사도 검증 → 완주 스탬프 발급, 이 핵심 루프 하나를 끝까지 동작시키는 것.

## 도메인

| 도메인 | 책임 |
|---|---|
| Auth/User | 소셜 로그인 (카카오 우선, provider 확장 가능한 구조) |
| Course | 코스 목록/상세, 공식 경로 데이터 (읽기 전용, 관리자가 미리 등록) |
| Running Record | GPS 기록 시작/일시정지/종료, 경로+거리+시간 저장 |
| Course Verification | 기록 vs 공식 경로 일치율 판정. 지금은 server 안 스텁(항상 통과), 4단계에서 lambda로 이동 + PostGIS(ST_Buffer/ST_DWithin) 실제 로직 |
| Stamp | 검증 통과 시 발급. (user_id, course_id) 유니크로 코스당 1회만 |
| Notice | 공지사항 목록/상세 조회, 홈 화면에 노출 (읽기 전용, 관리자가 직접 등록) |

## MVP 범위

### 포함

- Auth: 카카오 로그인, 애플 로그인
- Course: 목록/상세 조회 API
- Running Record: 시작/일시정지/종료, 경로 저장
- Course Verification: 스텁 (항상 통과)
- Stamp: 발급 + 스탬프북 조회
- Notice: 공지사항 목록 조회 API (홈 화면에 노출)

### 제외 (나중 단계)

- 협력업체(Partner) — 지도 제휴 업체, 혜택, 셀프 등록
- 커뮤니티, 포인트/리워드, 알림(푸시), 테마 큐레이션
- 소셜 로그인 확장 (Google)
- 이용약관/개인정보처리방침 등 법적 문서

## 도메인별 기능 쪼개기

> 여기서부터 도메인 하나씩 요구사항을 더 잘게 쪼개면서 채워나가기.

### Auth/User

- [ ] 카카오 로그인 (SDK → access token 서버 전달)
- [ ] 애플 로그인 (Sign in with Apple, iOS)
- [ ] 서버에서 카카오/애플 토큰 검증
- [ ] User에 apple_id 컬럼 추가 (nullable)
- [ ] 최초 로그인 시 자동 회원가입 (upsert)
- [ ] JWT access token 발급 (유효기간 1시간)
- [ ] refresh token 발급 및 저장 (유효기간 30일)
- [ ] refresh token으로 access token 재발급 API
- [ ] 인증 필요한 API 토큰 검증 (dependency)
- [ ] 로그아웃 (refresh token 폐기)
- [ ] 회원 탈퇴 (계정 삭제) API

**보류 / 검토 필요**
- refresh token rotation 여부 — 미정
- 애플 로그인 — iOS 배포 확정. 소셜 로그인 제공 시 애플 로그인 동반 요구(가이드라인 4.8)라 필수로 전환
- 회원 탈퇴 — iOS 배포 확정으로 앱스토어 심사 가이드라인(5.1.1v) 상 필수로 전환
- 카카오/애플 계정 연동 — MVP는 지원 안 함, provider별로 별개 계정. 필요해지면 로그인 상태에서 다른 provider 연동하는 플로우 추가
- 애플 로그인 — 시뮬레이터에서 end-to-end 동작 확인 완료(2026-08-09). 시뮬레이터는
  서명을 안 해서 인증서·프로파일·entitlement 없이 되므로, 팀원도 개발자 계정 없이
  `flutter run`으로 테스트할 수 있다(setup.md). 실기기·배포는 별도.

**배포 준비 (개발 외)**
- [ ] 카카오 개발자 계정 생성 + 앱 등록
- [ ] 카카오 플랫폼 등록 (Android 키 해시, iOS 번들ID, Web 도메인)
- [ ] 개인정보처리방침 문서 작성 + 호스팅 (URL 확보)
- [ ] 서비스(홈페이지) URL 준비
- [ ] Android 릴리즈 키스토어 생성 + 릴리즈 키 해시 카카오 콘솔 등록
- [ ] Apple Developer Program 가입 ($99/년)
- [ ] 카카오 로그인 실 서비스 전환

**Apple 로그인 (시뮬레이터까지 완료)**
- [x] Apple Developer Program 가입, App ID에 Sign In with Apple capability 활성화
- [x] 개발 인증서 발급 (Apple Development, 팀 `G92RR9396W`)
- [x] `ios/Flutter/Signing.xcconfig`에 Team ID 설정 — 팀 공용이라 커밋해서 공유
- [x] `Runner.entitlements`에 `com.apple.developer.applesignin` 키 추가. 시뮬레이터
  빌드에는 적용되지 않지만 실기기·배포 빌드에 필요하다.
- [x] 시뮬레이터에서 `POST /auth/apple` 플로우 확인 — 유저 생성·닉네임까지 통과

**Apple 로그인 (실기기·배포용, 남음)**
- [ ] 아이폰 UDID 등록 — 등록 기기 0대면 프로비저닝 프로파일 발급이 거부된다
- [ ] 실기기 빌드로 App ID capability가 프로파일에 실렸는지 확인 (시뮬레이터에서는
  검증되지 않는 부분)
- [ ] 회원 탈퇴 시 애플 토큰 revoke — 심사 5.1.1(v). `.p8` 키 발급 + 앱이
  `authorizationCode`를 서버로 전달하도록 수정 필요

### Course

- [x] courses 테이블 (이름, 거리, 난이도, 태그, 주소, 근처 주차장/화장실, 설명, 경로 — 경로는 JSONB, 이유는 architecture.md)
- [x] 코스 목록 조회 API
- [x] 코스 상세 조회 API
- [x] User에 role 컬럼 추가 (user/admin)
- [x] 코스 등록 API (`POST /courses/gpx`, admin role 필요)

**결정됨**
- 코스 등록 입력 방식 — **GPX 업로드**로 확정. 관리자가 경로 플래너에서 그려
  내보낸 GPX를 `server/courses/`에 두고 `courses.yaml`에 나머지 정보를 적으면
  `push_courses.py`가 올린다. 자세한 내용은 architecture.md의
  "코스 데이터 파이프라인".
- 코스는 **관리자만 올린다.** 달린 경로를 코스로 등록하던 `POST /courses`와 그
  화면을 지웠다. 주소가 필수값이 되면서 "달리고 나서 즉석 등록"과 맞지 않고,
  공식 코스만 노출하기로 했으므로 사용자 등록 경로를 남길 이유가 없다.
- 코스 수정·재업로드를 코드로 다루지 않는다. slug와 upsert를 걷어냈고, 고칠
  일은 DB에서 직접 처리한다. 배경은 architecture.md.

**보류 / 검토 필요**
- 관리자 신청 셀프서비스 플로우 — 나중 단계

### Running Record

- [ ] 러닝 제출 API (종료 시 1회 호출)
- [ ] running_records 테이블 (user_id, course_id, path, distance, duration, started_at, completed_at)
- [ ] 내 러닝 기록 목록 조회 API
- [ ] 앱: GPS 로컬 DB 저장
- [ ] 앱: 일시정지/재개
- [ ] 앱: 총 시간 + 일시정지 시간 표시

**보류 / 검토 필요**
- 코스 없는 자유 러닝 — MVP 제외 후보
- 실시간 진행률(%) 미표시 — 통과 기준은 서버만 앎
- 총 시간/일시정지 시간 표시 방식 — 상의해서 확정 필요

### Course Verification

- [ ] 검증 로직 스텁 (항상 pass 반환)
- [ ] 러닝 제출 API에서 스텁 호출 → 결과로 pass/fail 반환

**보류 / 검토 필요**
- 실제 판정 로직 (버퍼 폭, 커버리지 임계값) — 4단계(lambda + PostGIS)에서 설계
- GPS 오차 허용 범위 — 4단계에서 튜닝
- 판정 연산 위치: CPU(현재 Python coverage_ratio) vs PostGIS(ST_DWithin/ST_FrechetDistance) — 전자는 무거워지면 별도 서버 분리 필요, 후자는 DB로 병목 이동 + PostGIS 확장/geography 컬럼 전환 필요. 부하 실측 전까지는 결정 보류
- 판정 알고리즘 후보: 체크포인트 시퀀스 방식(코스 위 웨이포인트 순서대로 통과 확인) — 연산량 적고 방향(역주행)도 자연히 걸러짐. 아직 확정 아님

### Stamp

- [ ] stamps 테이블 (user_id, course_id — 유니크)
- [ ] 검증 통과 시 스탬프 자동 발급
- [ ] 내 스탬프북 조회 API

### Notice

- [x] 홈 화면 UI (공지사항 카드 리스트, 더미 데이터)
- [x] notices 테이블 (제목, 본문, 작성일)
- [x] 공지사항 목록 조회 API (로그인 필요)
- [x] 공지사항 작성 API (`POST /notices`, admin role 필요)
- [x] 앱: 더미 데이터 → API 연동으로 교체
- [x] 공지 작성 화면 (홈 AppBar 버튼 → `NoticeCreateScreen`)
- [x] 작성 버튼 admin 전용으로 제한 (`AdminOnly` 위젯 — 화면 정리용, 권한 판정은 서버)

**보류 / 검토 필요**
- 관리자 화면 필요 시점 — 당장은 사람이 API로 직접 등록, 필요해지면 앱/웹에 작성 화면 추가
