#!/usr/bin/env bash
# 构建 ad-hoc 签名的 GitHub Release 安装包（zip + dmg）。
#
#   scripts/release-github.sh
#
# 产物在 dist/ 下：Liteshot-<版本>.dmg、Liteshot-<版本>-macOS.zip 及 .sha256。
# 发布用 gh release create（见 docs/发布.md）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "${VERSION}" ]]; then
  echo "读不到 MARKETING_VERSION" >&2
  exit 1
fi

DIST="${DIST:-$ROOT/dist}"
APP="$(CONFIG=Release "$ROOT/scripts/build.sh" | tail -n1)"
if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在：$APP" >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"

ZIP="$DIST/Liteshot-${VERSION}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

DMG="$DIST/Liteshot-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Liteshot.app"
hdiutil create -quiet -volname "Liteshot ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

shasum -a 256 "$ZIP" "$DMG" | tee "$DIST/SHA256SUMS"
echo
echo "GitHub Release 产物："
echo "  $DMG"
echo "  $ZIP"
