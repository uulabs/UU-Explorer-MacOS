#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${UU_ICON_WORK_DIR:-$ROOT/.build/icon-work}"

if [[ ! -x /usr/bin/swift ]]; then
  echo "swift not found" >&2
  exit 1
fi

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/AppIcon.iconset"
/usr/bin/swift "$ROOT/scripts/make-icon.swift" "$SCRATCH/icon-1024.png"

make_size() {
  local size="$1"
  local name="$2"
  /usr/bin/sips -z "$size" "$size" "$SCRATCH/icon-1024.png" --out "$SCRATCH/AppIcon.iconset/$name" >/dev/null
}

make_size 16 icon_16x16.png
make_size 32 icon_16x16@2x.png
make_size 32 icon_32x32.png
make_size 64 icon_32x32@2x.png
make_size 128 icon_128x128.png
make_size 256 icon_128x128@2x.png
make_size 256 icon_256x256.png
make_size 512 icon_256x256@2x.png
make_size 512 icon_512x512.png
make_size 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$SCRATCH/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
