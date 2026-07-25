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

## MVP 범위

### 포함

- Auth: 카카오 로그인만
- Course: 목록/상세 조회 API
- Running Record: 시작/일시정지/종료, 경로 저장
- Course Verification: 스텁 (항상 통과)
- Stamp: 발급 + 스탬프북 조회

### 제외 (나중 단계)

- 협력업체(Partner) — 지도 제휴 업체, 혜택, 셀프 등록
- 커뮤니티, 포인트/리워드, 알림/공지사항, 테마 큐레이션
- 소셜 로그인 확장 (Apple, Google)
- 이용약관/개인정보처리방침 등 법적 문서

## 도메인별 기능 쪼개기

> 여기서부터 도메인 하나씩 요구사항을 더 잘게 쪼개면서 채워나가기.

### Auth/User

- [ ] 카카오 로그인 (SDK → access token 서버 전달)
- [ ] 서버에서 카카오 토큰 검증
- [ ] 최초 로그인 시 자동 회원가입 (upsert)
- [ ] JWT access token 발급 (유효기간 12~24시간)
- [ ] 인증 필요한 API 토큰 검증 (dependency)
- [ ] 로그아웃

**보류 / 검토 필요**
- refresh token 미도입 — access token 유효기간을 길게 잡아 대체
- 회원 탈퇴 — MVP 제외

### Course

- [ ] courses 테이블 (이름, 난이도, 거리, 고도, 설명, 경로, 시작점 — 경로는 geometry(LineString))
- [ ] 코스 목록 조회 API
- [ ] 코스 상세 조회 API
- [ ] User에 role 컬럼 추가 (user/admin)
- [ ] 코스 등록 API (admin 전용)

**보류 / 검토 필요**
- 코스 등록 입력 방식 — GPX 제공 여부 문의 필요 (업로드 vs 관리자 GPS 기록)
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
