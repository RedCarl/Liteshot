#!/usr/bin/env bash
# Liteshot 发布脚本（Developer ID + 公证 + Sparkle appcast）
# 需要预先准备：
#   TEAM_ID, APPLE_ID, APP_PASSWORD（App 专用密码）, SIGN_IDENTITY
#   SPARKLE_BIN（Sparkle 包内 bin 目录，含 generate_appcast）
set -euo pipefail

: "${TEAM_ID:?请设置 TEAM_ID}"
: "${APPLE_ID:?请设置 APPLE_ID}"
: "${APP_PASSWORD:?请设置 APP_PASSWORD（App 专用密码）}"
: "${SIGN_IDENTITY:?请设置 SIGN_IDENTITY（Developer ID Application: ...）}"
: "${SPARKLE_BIN:?请设置 SPARKLE_BIN（Sparkle/bin 目录）}"

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"

cd "$ROOT"
xcodegen generate

xcodebuild \
  -project Liteshot.xcodeproj \
  -scheme Liteshot \
  -configuration Release \
  -archivePath "$ROOT/build/Liteshot.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$ROOT/build/Liteshot.xcarchive/Products/Applications/Liteshot.app" "$OUT/"

codesign --deep --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" "$OUT/Liteshot.app"
codesign --verify --deep --strict --verbose=2 "$OUT/Liteshot.app"

ditto -c -k --keepParent "$OUT/Liteshot.app" "$OUT/Liteshot-$VERSION.zip"

xcrun notarytool submit "$OUT/Liteshot-$VERSION.zip" \
  --apple-id "$APPLE_ID" \
  --password "$APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

xcrun stapler staple "$OUT/Liteshot.app"
xcrun stapler validate "$OUT/Liteshot.app"

# 生成 Sparkle appcast（需要 Sparkle 私钥已导入钥匙串）
"$SPARKLE_BIN/generate_appcast" "$OUT"

echo "完成：$OUT"
echo "下一步：把 Liteshot-$VERSION.zip、appcast.xml 上传到 SUFeedURL 指向的位置"
