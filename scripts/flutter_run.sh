#!/usr/bin/env bash
#
# 로컬 백엔드를 물린 채로 안드로이드 기기에 앱을 띄운다. (macOS / Linux)
# 윈도우는 scripts/flutter_run.ps1 을 쓴다.
#
# 실기기에서 그냥 `flutter run`을 하면 로컬 서버에 닿지 못하고 30초 뒤
# connectionTimeout이 난다. 앱의 디버그 기본값(frontend/app/lib/config/app_config.dart)이
# 10.0.2.2인데, 그건 에뮬레이터의 가상 NAT가 호스트 루프백으로 넘겨주는 별칭이라
# 실기기에는 그런 주소가 없기 때문이다. 맥에 안드로이드 실기기를 꽂아도 똑같다.
#
# 그래서 이 스크립트가 두 가지를 대신한다:
#   1. adb reverse — 기기의 127.0.0.1:PORT 를 USB로 이 컴퓨터의 같은 포트에 연결한다.
#   2. --dart-define=API_BASE_URL — 앱이 그 127.0.0.1 을 보게 한다.
#
# LAN IP를 알 필요도, 방화벽을 열 필요도 없다. adb reverse는 에뮬레이터도 지원한다.
#
# adb reverse는 기기를 다시 꽂거나 재부팅하면 풀린다. 그래서 `flutter run`을 직접
# 치지 않고 매번 이 스크립트로 실행한다.
#
# iOS 실기기는 대상이 아니다(adb는 안드로이드 전용). iOS 실기기는 맥의 LAN IP를
# --dart-define으로 직접 넘겨야 한다.
#
# 사용법:
#   ./scripts/flutter_run.sh
#   ./scripts/flutter_run.sh --device R3CT30ABCDE
#   ./scripts/flutter_run.sh --port 8000 -- --verbose

set -euo pipefail

PORT=8000
DEVICE_ID=""
EXTRA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --port)   PORT="$2"; shift 2 ;;
    --device) DEVICE_ID="$2"; shift 2 ;;
    --)       shift; EXTRA=("$@"); break ;;
    *)        EXTRA+=("$1"); shift ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/frontend/app"

# adb는 PATH에 없는 경우가 흔하다(안드로이드 스튜디오가 PATH를 안 건드린다).
# 그래서 SDK 위치를 직접 뒤진다. 맥 기본 경로는 ~/Library/Android/sdk 다.
resolve_adb() {
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi

  local root
  for root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
              "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -n "$root" ] || continue
    if [ -x "$root/platform-tools/adb" ]; then
      echo "$root/platform-tools/adb"
      return
    fi
  done

  echo "adb를 찾지 못했어요. 안드로이드 SDK를 설치하고 ANDROID_HOME을 설정하거나, platform-tools를 PATH에 넣어주세요." >&2
  exit 1
}

ADB="$(resolve_adb)"

# `adb devices` 출력에서 상태가 device인 것만 시리얼로 뽑는다.
# (unauthorized/offline은 reverse가 안 되므로 제외한다 — 여기서 걸러야 원인이 분명해진다.)
DEVICES=$("$ADB" devices | tail -n +2 | awk '$2 == "device" { print $1 }')

if [ -z "$DEVICES" ]; then
  echo '연결된 안드로이드 기기가 없어요. USB 디버깅을 켜고, 기기 화면의 "USB 디버깅을 허용하시겠습니까?"를 승인했는지 확인해주세요.' >&2
  exit 1
fi

DEVICE_COUNT=$(echo "$DEVICES" | wc -l | tr -d ' ')

if [ -n "$DEVICE_ID" ]; then
  if ! echo "$DEVICES" | grep -qx "$DEVICE_ID"; then
    echo "'$DEVICE_ID' 기기를 찾지 못했어요. 붙어 있는 기기: $(echo "$DEVICES" | tr '\n' ' ')" >&2
    exit 1
  fi
elif [ "$DEVICE_COUNT" -gt 1 ]; then
  echo "기기가 여러 대 붙어 있어요: $(echo "$DEVICES" | tr '\n' ' ')" >&2
  echo "  --device 로 하나를 골라주세요." >&2
  exit 1
else
  DEVICE_ID="$DEVICES"
fi

# 서버가 안 떠 있으면 앱은 결국 또 타임아웃을 볼 뿐이다. 여기서 미리 알려준다.
if ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "경고: 127.0.0.1:$PORT 에 아무것도 안 떠 있어요. 서버를 먼저 띄우세요 — ./scripts/local_docker_start.sh up" >&2
fi

"$ADB" -s "$DEVICE_ID" reverse "tcp:$PORT" "tcp:$PORT"
echo "▶ adb reverse: $DEVICE_ID 의 127.0.0.1:$PORT → 이 컴퓨터의 $PORT"

echo "▶ flutter run -d $DEVICE_ID --dart-define=API_BASE_URL=http://127.0.0.1:$PORT ${EXTRA[*]:-}"

cd "$APP_DIR"
exec flutter run -d "$DEVICE_ID" \
  "--dart-define=API_BASE_URL=http://127.0.0.1:$PORT" \
  ${EXTRA[@]+"${EXTRA[@]}"}
