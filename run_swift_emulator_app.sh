#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BIN="$ROOT_DIR/build/Tempest AI.app/Contents/MacOS/TempestAI"

if [[ ! -x "$APP_BIN" ]]; then
    "$ROOT_DIR/build_app.sh"
fi

exec "$APP_BIN"
