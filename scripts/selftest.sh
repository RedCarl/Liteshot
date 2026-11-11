#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -n1)"
BIN="$APP/Contents/MacOS/Liteshot"

for flag in \
  --selftest --selftest-save --selftest-editor --selftest-document \
  --selftest-scroll --selftest-scrollh --selftest-panorama \
  --selftest-ocr --selftest-history --selftest-pixel --selftest-shortcut
do
  echo "== $flag =="
  "$BIN" "$flag" || exit 1
done
