#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE_ID="EDD9B083-63F1-44E6-9A7B-0A6964CC2561"
APP_PATH="$ROOT_DIR/build/Build/Products/Debug-iphonesimulator/AmplitudeDemo.app"

/opt/homebrew/bin/xcodegen generate --spec "$ROOT_DIR/project.yml"

xcodebuild \
  -project "$ROOT_DIR/AmplitudeDemo.xcodeproj" \
  -scheme AmplitudeDemo \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$ROOT_DIR/build" \
  build

if [[ "${1:-}" == "--reset" ]]; then
  xcrun simctl uninstall "$DEVICE_ID" com.cognition.amplitudedemo || true
fi

xcrun simctl install "$DEVICE_ID" "$APP_PATH"
SIMCTL_CHILD_AMPLITUDE_API_KEY="${AMPLITUDE_API_KEY:-}" \
  xcrun simctl launch --terminate-running-process booted com.cognition.amplitudedemo
