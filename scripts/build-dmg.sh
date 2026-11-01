#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/UU Explorer.app"
WORK="${UU_DMG_WORK_DIR:-$ROOT/.build/dmg-work}"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
DMG="$DIST/UU Explorer $VERSION.dmg"
VOLNAME="UU Explorer $VERSION"
STAGE="$WORK/dmg-stage"
SNAPSHOT="$WORK/dmg-smoke.png"
MOUNT_PATH=""

mkdir -p "$WORK" "$DIST"
if [[ "$STAGE" != "$WORK/dmg-stage" ]]; then
  echo "Refusing to clean an unexpected staging path." >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi

/usr/bin/codesign --verify --deep --strict "$APP"

cleanup() {
  if [[ -n "$MOUNT_PATH" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_PATH" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

rm -rf "$STAGE"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/UU Explorer.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
/usr/bin/hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

/usr/bin/hdiutil verify "$DMG" >/dev/null

ATTACH_OUTPUT="$(/usr/bin/hdiutil attach -nobrowse -readonly "$DMG")"
MOUNT_PATH="$(printf '%s\n' "$ATTACH_OUTPUT" | /usr/bin/awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
if [[ -z "$MOUNT_PATH" || ! -d "$MOUNT_PATH" ]]; then
  echo "Could not determine the mounted DMG path." >&2
  exit 1
fi

if [[ ! -d "$MOUNT_PATH/UU Explorer.app" ]]; then
  echo "DMG is missing UU Explorer.app" >&2
  exit 1
fi
if [[ ! -L "$MOUNT_PATH/Applications" || "$(readlink "$MOUNT_PATH/Applications")" != "/Applications" ]]; then
  echo "DMG is missing the Applications shortcut" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$MOUNT_PATH/UU Explorer.app"

rm -f "$SNAPSHOT"
"$MOUNT_PATH/UU Explorer.app/Contents/MacOS/UU Explorer" \
  --path "$ROOT" \
  --snapshot "$SNAPSHOT" \
  --appearance light >/dev/null 2>&1
if [[ ! -s "$SNAPSHOT" ]]; then
  echo "App launch from mounted DMG failed." >&2
  exit 1
fi

/usr/bin/hdiutil detach "$MOUNT_PATH" >/dev/null
MOUNT_PATH=""
cleanup
trap - EXIT

/usr/bin/hdiutil imageinfo "$DMG" >/dev/null
echo "Built $DMG"
ls -lh "$DMG"
