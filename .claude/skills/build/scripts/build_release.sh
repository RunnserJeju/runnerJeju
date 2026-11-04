#!/usr/bin/env bash
#
# 앱 릴리즈 빌드를 한 번에: Android AAB(플레이콘솔 업로드용) + iOS 아카이브(Xcode Organizer).
# 끝나면 Finder에 AAB를 띄우고, 아카이브를 Xcode로 열어 Organizer에서 바로 확인/배포한다.
#
#   bash .claude/skills/build/scripts/build_release.sh            # 둘 다
#   bash .claude/skills/build/scripts/build_release.sh android    # AAB만
#   bash .claude/skills/build/scripts/build_release.sh ios        # 아카이브만
#   bash .claude/skills/build/scripts/build_release.sh --no-open  # 빌드만, 창 안 띄움
#   bash .claude/skills/build/scripts/build_release.sh --debug-key  # key.properties 없어도 AAB 빌드(업로드 불가)
#
# - AAB: 플레이콘솔은 릴리즈 키 서명만 받는다. android/key.properties가 없으면 debug 키로
#   서명돼 업로드가 거부되므로 기본은 중단한다. 파이프라인 확인용이면 --debug-key.
# - iOS: `flutter build ipa`가 build/ios/archive/Runner.xcarchive를 만든다. ipa export는
#   서명 설정에 따라 실패할 수 있는데, 아카이브만 있으면 Organizer에서 Distribute로 올릴 수
#   있으므로 export 실패는 경고로만 알리고 계속 간다.
# - 아카이브를 `open`하면 Xcode가 Organizer에 등록해 보여준다.

set -uo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
APP="$ROOT/frontend/app"
TARGET="all"
OPEN=1
DEBUG_KEY=0
for arg in "$@"; do
  case "$arg" in
    android|ios|all) TARGET="$arg" ;;
    --no-open) OPEN=0 ;;
    --debug-key) DEBUG_KEY=1 ;;
    *) echo "모르는 인자: $arg" >&2; exit 2 ;;
  esac
done

cd "$APP"
VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
echo "== 버전 $VERSION"

AAB="$APP/build/app/outputs/bundle/release/app-release.aab"
ARCHIVE="$APP/build/ios/archive/Runner.xcarchive"
FAIL=0

if [ "$TARGET" != "ios" ]; then
  echo "== Android AAB"
  if [ ! -f "$APP/android/key.properties" ] && [ "$DEBUG_KEY" = 0 ]; then
    echo "!! android/key.properties가 없어 debug 키로 서명됩니다 — 플레이콘솔에 올릴 수 없어요." >&2
    echo "   릴리즈 키스토어를 둔 뒤 다시 하거나, 확인용이면 --debug-key로 강제하세요." >&2
    FAIL=1
  else
    rm -f "$AAB"
    if flutter build appbundle --release; then
      [ -f "$APP/android/key.properties" ] || echo "   (debug 키 서명 — 업로드 불가, 확인용)"
    else
      echo "!! AAB 빌드 실패" >&2; FAIL=1
    fi
  fi
fi

if [ "$TARGET" != "android" ]; then
  echo "== iOS 아카이브"
  # 지난 빌드 산출물을 지워 둔다 — 안 그러면 export 실패 시 옛 ipa가 결과로 잡힌다.
  rm -rf "$ARCHIVE" "$APP/build/ios/ipa"
  # export 실패(프로비저닝 프로파일 등)여도 flutter는 0으로 끝난다. 아카이브 유무로 판단한다.
  if ! flutter build ipa --release; then
    if [ -d "$ARCHIVE" ]; then
      echo "   (ipa export는 실패했지만 아카이브는 만들어짐 — Organizer에서 Distribute 가능)"
    else
      echo "!! iOS 아카이브 빌드 실패" >&2; FAIL=1
    fi
  elif [ ! -d "$ARCHIVE" ]; then
    echo "!! iOS 아카이브가 만들어지지 않음" >&2; FAIL=1
  fi
fi

echo "== 결과"
[ -f "$AAB" ] && echo "   AAB: $AAB ($(du -h "$AAB" | cut -f1))"
[ -d "$ARCHIVE" ] && echo "   아카이브: $ARCHIVE"
IPA="$(ls -t "$APP"/build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"
[ -n "$IPA" ] && echo "   IPA: $IPA"

if [ "$OPEN" = 1 ]; then
  [ "$TARGET" != "ios" ] && [ -f "$AAB" ] && open -R "$AAB"
  [ "$TARGET" != "android" ] && [ -d "$ARCHIVE" ] && open "$ARCHIVE"
fi

exit $FAIL
