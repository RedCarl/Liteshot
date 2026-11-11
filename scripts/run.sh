#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -n1)"
open "$APP"
echo "已启动：$APP"
