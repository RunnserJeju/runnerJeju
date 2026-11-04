---
name: build
description: 앱 스토어 업로드용 릴리즈 빌드. Android AAB(플레이콘솔)와 iOS 아카이브(Xcode Organizer)를 만들고, Finder에 AAB를 띄우고 Xcode Organizer를 열어 바로 확인·배포할 수 있게 한다. "빌드해", "aab 뽑아줘", "아카이브 떠줘", "/build" 요청에 사용.
argument-hint: "[android|ios|all] [--no-open] [--debug-key]"
---

# build

`scripts/build_release.sh` 하나로 두 플랫폼의 스토어 업로드용 빌드를 돌리고 결과물을 바로 열어 준다.

## 사용법

| 사용자 요청 | 실행 |
|---|---|
| 빌드 / 둘 다 | `bash .claude/skills/build/scripts/build_release.sh` |
| aab만 / 안드로이드만 | `bash .claude/skills/build/scripts/build_release.sh android` |
| ios만 / 아카이브만 | `bash .claude/skills/build/scripts/build_release.sh ios` |
| 열지 말고 빌드만 | `... --no-open` |
| 키 없이 확인용 AAB | `... --debug-key` (업로드 불가) |

저장소 어디서 실행해도 된다(스크립트가 저장소 루트를 찾는다).

## 하는 일

1. `flutter build appbundle --release` → `frontend/app/build/app/outputs/bundle/release/app-release.aab`
2. `flutter build ipa --release` → `frontend/app/build/ios/archive/Runner.xcarchive` (+ export가 되면 `build/ios/ipa/*.ipa`)
3. Finder에서 AAB를 선택한 상태로 띄움(`open -R`) → 플레이콘솔에 드래그해 업로드
4. 아카이브를 Xcode로 열어 Organizer에 등록(`open Runner.xcarchive`) → Distribute App / TestFlight 업로드는 Organizer에서 사용자가 직접

## 규칙

1. 빌드는 수 분 걸린다. `run_in_background`로 실행하고 끝나면 결과 경로와 크기를 보고한다. 둘을 동시에 돌리지 말 것(스크립트가 순서대로 한다).
2. 빌드 전에 `flutter analyze`를 먼저 돌려 이슈가 없는지 본다. 이슈가 있으면 빌드하지 않고 알린다.
3. `pubspec.yaml`의 `version`을 결과에 같이 적는다. 스토어에 같은 빌드 번호는 두 번 못 올리므로 버전/빌드 번호를 올렸는지 사용자에게 확인한다(스크립트는 올리지 않는다).
4. **AAB는 릴리즈 키 서명이 필수다.** `frontend/app/android/key.properties`가 없으면 스크립트가 AAB를 만들지 않고 멈춘다. 이때는 키스토어가 있는 환경에서 빌드해야 한다고 알린다. `--debug-key`는 파이프라인 확인용일 뿐 업로드가 거부된다.
5. ipa export가 실패해도 아카이브가 있으면 성공으로 본다. Organizer에서 바로 Distribute할 수 있기 때문이다. 아카이브 자체가 없으면 실패이고, 출력 마지막 30줄을 보고한다.
6. APK(`flutter build apk`)나 `flutter build ios`(Runner.app)는 쓰지 않는다. 플레이콘솔은 AAB만 받고, Runner.app은 Organizer에 뜨지 않는다.
