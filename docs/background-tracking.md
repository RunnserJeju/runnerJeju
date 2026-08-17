# 백그라운드 러닝 트래킹 (iOS · Android)

러닝 앱은 **화면을 끄고 주머니에 넣은 채로도 경로·거리가 쌓여야** 한다. 이건
있으면 좋은 기능이 아니라 러닝 앱의 전제다. 이 문서는 **지금 왜 안 되는지**,
**최소 변경으로 어떻게 되게 하는지**, **실기기에서 어떻게 검증하는지**를 담는다.

출시 대상은 **iOS·Android 둘 다**이고, 백그라운드 수집은 양쪽 다 필수다.

---

## 1. 지금 상황 — 백그라운드로 가면 기록이 멈춘다

지금은 **의도적으로 꺼져 있다.** [`Info.plist`](../frontend/app/ios/Runner/Info.plist)에
직접 그렇게 적혀 있다("화면을 켜 둔 채로만 기록하고 백그라운드 위치를 쓰지 않아서
… 백그라운드 기록을 넣을 때 함께 추가한다"). 즉 나중에 할 일로 미뤄둔 것이고,
이 문서가 그 "나중"이다.

증상은 **화면을 끄거나 앱을 내리면 거리·경로가 그 자리에서 멈춘다.** 원인은 세 곳:

| # | 위치 | 지금 상태 | 결과 |
| --- | --- | --- | --- |
| ① | [`Info.plist`](../frontend/app/ios/Runner/Info.plist) | `UIBackgroundModes` 없음 | iOS가 백그라운드 진입 몇 초 뒤 앱을 정지 → 위치 스트림 멈춤 |
| ② | [`AndroidManifest.xml`](../frontend/app/android/app/src/main/AndroidManifest.xml) | `FOREGROUND_SERVICE` 권한 없음 | Doze/앱 스탠바이가 백그라운드 위치를 조임 → 수집 끊김 |
| ③ | [`location_service.dart`](../frontend/app/lib/services/location_service.dart) | 공통 `LocationSettings`만 사용 | 백그라운드를 켜는 플랫폼별 옵션(포그라운드 서비스·`allowBackgroundLocationUpdates`)이 안 걸림 |

> **이미 잘 돼 있는 것 — 여기는 건드리지 않는다.**
> [`run_tracker.dart`](../frontend/app/lib/services/run_tracker.dart)의 경과 시간은
> 1초 타이머가 아니라 **시작·종료 시각의 차**로 잰다(`elapsed` 게터). 타이머는
> 백그라운드에서 느려지거나 멈추지만 시각차는 안 틀린다. 그래서 **위치 스트림만
> 살리면** 거리·페이스·경로 누적 로직은 그대로 맞게 돌아간다. 트래킹 계층을
> 다시 짤 필요가 없다.

---

## 2. 어떻게 바꿀 건지 — Plan

### 2.0 두 갈래 중 무엇으로 가나 (결론부터)

백그라운드 위치를 유지하는 방법은 사실상 두 가지다.

| 방식 | 무엇 | 이 프로젝트엔 |
| --- | --- | --- |
| **A. 세션형 (권장)** | 사용자가 러닝을 시작하는 동안만 위치를 유지. iOS는 "앱 사용 중" 권한 + 백그라운드 모드, Android는 포그라운드 서비스(+상시 알림) | ✅ **이걸로 간다** |
| B. 상시형 | 앱이 완전히 죽어도 위치를 받음. iOS "항상 허용", Android `ACCESS_BACKGROUND_LOCATION` | ❌ 러닝 세션엔 과함 · 심사 부담 큼 |

**러닝은 사용자가 직접 시작하고 끝내는 세션**이다. 앱이 죽은 뒤에도 몰래 위치를
받을 이유가 없다. A는 권한 요청이 가볍고("항상 허용"을 안 물어봄) 스토어 심사
소명도 단순하다. 아래는 전부 **A 기준**이다.

### 2.1 iOS — Apple 정책이 핵심

여기가 사람들이 제일 헷갈리는 지점이라 따로 짚는다. iOS 위치 권한은 두 단계다.

- **"앱 사용 중 허용" (When In Use)** — 앱이 화면에 보일 때만 위치. 기본값.
- **"항상 허용" (Always)** — 앱이 백그라운드·종료 상태여도 위치.

여기서 **오해**: "백그라운드에서 받으려면 '항상 허용'이 필요하다" → **아니다.**

> **"앱 사용 중" 권한 + `UIBackgroundModes: location`** 조합이면, 러닝처럼
> 사용자가 시작한 세션 동안에는 화면을 꺼도 위치가 계속 들어온다. 대신 iOS가
> **상단에 파란색 위치 표시줄**을 띄운다("이 앱이 지금 위치를 쓰는 중"). 이게
> 정상이고, 런키퍼·나이키런·스트라바 같은 앱이 다 이 방식이다.

**"항상 허용"을 요청하면 생기는 비용**:
- 사용자에게 "항상 허용하시겠어요?"를 한 번 더 물어야 하고, iOS는 며칠 뒤
  "이 앱이 백그라운드에서 N번 위치를 썼어요, 계속?"이라고 **재확인 팝업**을 띄운다.
  → 이탈 포인트가 늘고, 실제 러닝 세션 트래킹엔 이 권한이 필요 없다.
- App Store 심사에서 **"왜 항상 위치가 필요한가"를 소명**해야 한다. 세션형이라
  소명할 근거가 약해서 리젝 사유가 되기 쉽다.

그래서 **"항상 허용"은 요청하지 않는다.** 기존 `NSLocationWhenInUseUsageDescription`을
그대로 두고, 백그라운드 모드만 켠다.

**바꿀 것 — [`Info.plist`](../frontend/app/ios/Runner/Info.plist)**:
```xml
<!-- 러닝 세션 동안 화면을 꺼도 위치가 계속 들어오게 한다.
     "항상 허용"(NSLocationAlwaysAndWhenInUse)은 요청하지 않는다 —
     사용 중 권한 + 이 모드면 러닝 중 상단 파란 표시줄과 함께 백그라운드 수집이 유지된다. -->
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```
> 지금 95~98번 줄의 "백그라운드 위치를 쓰지 않는다"는 주석은 이제 사실과
> 어긋나므로 **함께 갱신**한다. 문서와 코드가 어긋나면 다음 사람이 헷갈린다.

### 2.2 Android — 포그라운드 서비스 + 상시 알림

Android는 백그라운드 위치를 강하게 조인다(Doze, 앱 스탠바이). 이걸 정면돌파하는
정석이 **포그라운드 서비스** — "지금 사용자가 보는 작업을 하고 있다"고 OS에
선언하고, 대가로 **없앨 수 없는 알림**을 하나 띄운다. geolocator가 이 서비스를
자동으로 띄워주므로 우리가 `Service` 클래스를 짤 필요는 없다. 권한만 열어주면 된다.

**바꿀 것 — [`AndroidManifest.xml`](../frontend/app/android/app/src/main/AndroidManifest.xml)**:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<!-- Android 14(API 34)+ 위치형 포그라운드 서비스에 필수 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```
> **`ACCESS_BACKGROUND_LOCATION`은 넣지 않는다.** 러닝은 사용자가 시작하고 알림이
> 계속 떠 있는 세션이라 이 권한 없이도 수집된다. 넣으면 Play 스토어 심사에서
> "왜 상시 백그라운드 위치가 필요한가"를 별도 영상·소명으로 증명해야 한다.
> `<service>` 선언도 우리가 안 적는다 — geolocator_android 플러그인이 자기
> 매니페스트에 이미 갖고 있고 병합된다.

### 2.3 위치 설정을 플랫폼별로 가른다

지금 [`location_service.dart`](../frontend/app/lib/services/location_service.dart)는
공통 `LocationSettings` 하나만 쓴다. 백그라운드를 켜는 옵션은 플랫폼마다 이름이
달라서, `AndroidSettings` / `AppleSettings`로 갈라준다.

```dart
import 'dart:io' show Platform;
// AndroidSettings·AppleSettings·ForegroundNotificationConfig는 geolocator가
// 이미 re-export하므로 하위 패키지를 따로 import할 필요 없다.

static LocationSettings get _trackingSettings {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
      // ★ 포그라운드 서비스를 띄워 백그라운드 수집을 유지시키는 핵심.
      //   이 config가 있어야 상시 알림이 뜨고 OS가 서비스를 안 죽인다.
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '러닝 기록 중',
        notificationText: '경로와 거리를 기록하고 있어요',
        enableWakeLock: true, // 화면이 꺼져도 CPU를 깨워 위치 콜백을 받는다.
      ),
    );
  }
  if (Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
      allowBackgroundLocationUpdates: true,     // ★ 백그라운드에서도 콜백 유지.
      showBackgroundLocationIndicator: true,    // 상단 파란 표시줄(정직하게 표시).
      pauseLocationUpdatesAutomatically: false, // iOS가 임의로 멈추지 않게.
      activityType: ActivityType.fitness,       // 피트니스 활동으로 힌트.
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 1,
  );
}
```
> `AndroidSettings` · `AppleSettings` · `ForegroundNotificationConfig` 타입은
> `geolocator`(14.0.3, 내부적으로 geolocator_android 5.0.3 · geolocator_apple
> 2.3.14를 물고 온다)가 **이미 re-export**한다. [`pubspec.yaml`](../frontend/app/pubspec.yaml)에
> **새 의존성도, 하위 패키지 import도 필요 없다** — `geolocator` 하나만 import하면 된다.

### 2.4 난이도 · 장단점 요약

| 항목 | 난이도 | 장점 | 주의점 |
| --- | --- | --- | --- |
| iOS Info.plist | ★☆☆ 매우 쉬움 | 키 하나. 코드 변경 없음 | 주석 갱신 잊지 말 것 |
| Android Manifest | ★☆☆ 매우 쉬움 | 권한 2줄. 서비스 코드는 플러그인이 처리 | `BACKGROUND_LOCATION`은 넣지 말 것 |
| location_service.dart | ★★☆ 보통 | 트래킹 로직·화면은 손 안 댐. 여기만 바뀜 | 알림 문구·아이콘 확인 |
| **전체** | **★★☆** | 파일 3개 + 주석. 아키텍처 변화 없음 | **실기기 검증이 진짜 일**(아래 3장) |

핵심은 **코드 변경은 작고, 위험은 "실기기에서 진짜 되는지"에 몰려 있다**는 것.
그래서 3장이 이 작업의 절반이다.

---

## 3. 테스트 — 실기기에서 반드시 확인

에뮬레이터·시뮬레이터로는 **판정 불가**다. 포그라운드 서비스 제약(Android)과 앱
정지(iOS)는 실제 기기·실제 백그라운드에서만 재현된다. 최소 **Android 14+ 실기기
1대, iPhone 1대**에서 확인한다.

### 3.1 핵심 시나리오 (양쪽 공통) — "주머니 테스트"

가장 확실한 건 실제로 걷는 것이다.

1. 러닝 시작
2. **전원 버튼으로 화면 끄기** (또는 홈으로 나가 다른 앱 열기)
3. **1~2분 실제로 걸어 이동**
4. 앱으로 복귀
5. **거리·경로가 끊김 없이 쌓여 있으면 성공.** 2번 시점에서 멈춰 있으면 실패.

> 걷기 어려우면 GPX 목(mock) 위치로 대체 가능(3.4). 단, **최종 확인은 실제 이동**으로
> 한 번은 한다 — 목 위치는 OS의 백그라운드 스로틀링을 그대로 재현하지 못한다.

### 3.2 iOS 전용 확인

- [ ] 러닝 시작 후 백그라운드로 가면 **상단에 파란 위치 표시줄**이 뜬다.
      (안 뜨면 `allowBackgroundLocationUpdates`나 `UIBackgroundModes`가 안 걸린 것)
- [ ] 권한 팝업이 **"앱 사용 중"만** 묻고 "항상 허용"은 안 묻는다.
- [ ] 화면 잠금(자동 잠금 포함) 상태로 1분 뒤 거리 증가.
- [ ] 설정 → 개인정보 보호 → 위치에서 이 앱이 **"앱을 사용하는 동안"**으로 떠 있다.

### 3.3 Android 전용 확인

- [ ] 러닝 시작 시 **알림 트레이에 "러닝 기록 중" 알림**이 뜨고, 스와이프로 안 지워진다.
- [ ] **Android 14+ 기기**에서 크래시 없이 서비스가 뜬다. (14+는 포그라운드
      서비스 타입 규칙이 엄격해 여기서 터지는 경우가 많다 — 반드시 14+에서 확인)
- [ ] 화면 끄고 1분 뒤 거리 증가.
- [ ] 배터리 최적화가 켜진 상태에서도 유지되는지(제조사별 커스텀 OS —
      삼성·샤오미 등은 더 공격적으로 죽인다. 여유되면 삼성 기기 1대 추가 확인).

### 3.4 목(mock) 위치로 빠르게 반복 — 실제 걷기 전 개발용

이 저장소엔 이미 시뮬레이션 위치원이 있다
([`lib/test/simulated_location_service.dart`](../frontend/app/lib/test/simulated_location_service.dart),
[`RunTracker.start(source:)`](../frontend/app/lib/services/run_tracker.dart)). 개발
중 로직 확인엔 이걸로 충분하다. 다만 이 시뮬레이터는 **앱 프로세스 안에서** 점을
쏘므로, **OS 레벨 백그라운드 스로틀링은 검증하지 못한다.** 로직 회귀 확인용이지
백그라운드 생존 확인용이 아니다.

OS 레벨 목 위치가 필요하면:
- **Android**: 개발자 옵션 → "모의 위치 앱 선택" + GPX 재생 앱.
- **iOS**: Xcode 실행 중 Debug → Simulate Location, 또는 `.gpx` 파일 지정.

### 3.5 회귀 — 끊김 복구가 그대로 되는지

백그라운드를 켜도 **기존 "위치 끊김 → 일시정지 → 재개" 로직**
([`run_tracker.dart`](../frontend/app/lib/services/run_tracker.dart)의
`_handlePositionLost`)은 그대로 살아 있어야 한다.

- [ ] 러닝 중 기기 **위치 서비스 자체를 끄면** "…멈췄어요" 안내가 뜨고 일시정지된다.
- [ ] 다시 켜고 **이어 달리기**를 누르면 재개된다.
- [ ] 백그라운드에서 위치를 잃었다가 복귀했을 때 시간·거리가 어긋나지 않는다
      (`elapsed`가 시각차 기반이라 원칙적으로 안전 — 그래도 눈으로 확인).

---

## 4. 출시 체크리스트 (스토어 심사 대비)

- [ ] **iOS**: `UIBackgroundModes: location` 추가, "항상 허용" 미요청 확인.
- [ ] **iOS**: `NSLocationWhenInUseUsageDescription` 문구가 "왜 위치를 쓰는지"를
      사용자 말로 설명하는지(현재 "달린 경로와 거리를 기록하기 위해…" — 유지 가능).
- [ ] **Android**: `FOREGROUND_SERVICE` · `FOREGROUND_SERVICE_LOCATION` 추가,
      `ACCESS_BACKGROUND_LOCATION` **미포함** 확인.
- [ ] **Android**: Play Console에서 위치 권한 사용 목적 선언 시 "포그라운드에서
      사용자 시작 러닝 트래킹"으로 기재(상시 백그라운드 아님).
- [ ] 두 플랫폼 모두 **실기기 주머니 테스트**(3.1) 1회 이상 통과.

> **보류 / 검토 필요**: 배터리 소모. `LocationAccuracy.best` + `distanceFilter: 1`은
> 정확하지만 배터리를 많이 쓴다. 백그라운드 장시간 러닝에서 소모가 문제되면
> 정확도를 `high`로, 필터를 늘리는 것을 검토(단, 지도 마커 부드러움과 트레이드오프 —
> [`run_tracker.dart`](../frontend/app/lib/services/run_tracker.dart)의 `_commitMeters`
> 게이트 설명 참고).
