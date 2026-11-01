#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${UU_BUILD_DIR:-$ROOT/.build}"
DIST="$ROOT/dist"
APP="$DIST/UU Explorer.app"

mkdir -p "$BUILD" "$DIST"
if [[ -n "${UU_SWIFT_MODULE_CACHE_PATH:-}" ]]; then
  export SWIFT_MODULE_CACHE_PATH="$UU_SWIFT_MODULE_CACHE_PATH"
  mkdir -p "$SWIFT_MODULE_CACHE_PATH"
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  "$ROOT/scripts/make-icon.sh"
fi

/usr/bin/swift build --package-path "$ROOT" -c release --scratch-path "$BUILD"

BINARY="$BUILD/release/Explorer"
if [[ ! -x "$BINARY" ]]; then
  echo "Release binary missing: $BINARY" >&2
  exit 1
fi

if [[ "$APP" != "$DIST/UU Explorer.app" ]]; then
  echo "Refusing to remove unexpected path: $APP" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/UU Explorer"
chmod 755 "$APP/Contents/MacOS/UU Explorer"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/xattr -cr "$APP" 2>/dev/null || true

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  SIGN_IDENTITY="$(printf '%s\n' "$IDENTITIES" | /usr/bin/awk -F'"' '/Developer ID Application:/ {print $2; exit}')"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(printf '%s\n' "$IDENTITIES" | /usr/bin/awk -F'"' '/Apple Development:/ {print $2; exit}')"
  fi
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "warning: no stable code-signing identity found; using ad-hoc. TCC permissions may reset after each rebuild." >&2
  SIGN_IDENTITY="-"
fi
/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP"
echo "Signed with: $SIGN_IDENTITY"

OLD_APP="$DIST/Explorer.app"
if [[ "$OLD_APP" == "$DIST/Explorer.app" && -d "$OLD_APP" ]]; then
  rm -rf "$OLD_APP"
fi

echo "Built $APP"
