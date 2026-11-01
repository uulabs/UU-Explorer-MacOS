#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
APP="$DIST/UU Explorer.app"
ZIP="$DIST/UU-Explorer-$VERSION.zip"
CHECKSUM="$ZIP.sha256"
DMG="$DIST/UU Explorer $VERSION.dmg"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi
/usr/bin/codesign --verify --deep --strict "$APP"

# Keep the bundle as the top-level item in the update archive.
rm -f "$ZIP" "$CHECKSUM"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && /usr/bin/shasum -a 256 "UU-Explorer-$VERSION.zip" > "UU-Explorer-$VERSION.zip.sha256")

if [[ ! -f "$DMG" ]]; then
  "$ROOT/scripts/build-dmg.sh"
fi

RELEASE_DMG="$DIST/UU-Explorer-$VERSION.dmg"
cp "$DMG" "$RELEASE_DMG"
(cd "$DIST" && /usr/bin/shasum -a 256 "UU-Explorer-$VERSION.dmg" > "UU-Explorer-$VERSION.dmg.sha256")

echo "Release assets:"
ls -lh "$ZIP" "$CHECKSUM" "$RELEASE_DMG" "$RELEASE_DMG.sha256"
