#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "需要 XcodeGen：brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
xcodebuild \
  -project Liteshot.xcodeproj \
  -scheme Liteshot \
  -configuration "${CONFIG:-Debug}" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/liteshot-build.log 2>&1 || {
    tail -40 /tmp/liteshot-build.log >&2
    exit 1
  }

APP="$(xcodebuild -project Liteshot.xcodeproj -scheme Liteshot -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/ {dir=$3} / FULL_PRODUCT_NAME/ {name=$3} END {print dir "/" name}')"
echo "$APP"
