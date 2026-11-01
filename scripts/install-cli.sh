#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${UU_CLI_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN"
ln -sf "$ROOT/scripts/uu" "$BIN/uu"
echo "Linked $BIN/uu -> $ROOT/scripts/uu"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Add $BIN to PATH: export PATH=\"$BIN:\$PATH\"" ;;
esac
