#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${UU_BUILD_DIR:-$ROOT/.build}"
if [[ -n "${UU_SWIFT_MODULE_CACHE_PATH:-}" ]]; then
  export SWIFT_MODULE_CACHE_PATH="$UU_SWIFT_MODULE_CACHE_PATH"
  mkdir -p "$SWIFT_MODULE_CACHE_PATH"
fi
mkdir -p "$BUILD"
/usr/bin/swift test --package-path "$ROOT" --scratch-path "$BUILD"
