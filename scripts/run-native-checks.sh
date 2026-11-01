#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${UU_NATIVE_CHECK_DIR:-$ROOT/.build/native-checks}"
mkdir -p "$WORK"
/usr/bin/swiftc -module-cache-path "$WORK/cache/swift-module-cache" \
  "$ROOT/Sources/Explorer/Support/ExplorerWindow.swift" "$ROOT/Tests/ExplorerWindowChecks/main.swift" \
  -o "$WORK/native-mouse-checks"
"$WORK/native-mouse-checks"
