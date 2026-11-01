# Releasing UU Explorer

The in-app updater consumes the **ZIP + `.sha256`** pair from the latest stable GitHub release. The DMG is for first-time installation.

## Checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run `swift test`.
3. Build and verify:

   ```bash
   ./scripts/build-app.sh
   ./scripts/build-dmg.sh
   ./scripts/build-release.sh
   ```

4. Commit and push the source changes.
5. Create a tag and GitHub release with the four assets:

   ```bash
   VERSION="1.19.0"
   git tag -a "v$VERSION" -m "UU Explorer $VERSION"
   git push origin "v$VERSION"

   gh release create "v$VERSION" \
     "dist/UU-Explorer-$VERSION.dmg" \
     "dist/UU-Explorer-$VERSION.dmg.sha256" \
     "dist/UU-Explorer-$VERSION.zip" \
     "dist/UU-Explorer-$VERSION.zip.sha256" \
     --title "UU Explorer $VERSION" \
     --notes-file path/to/release-notes.md \
     --latest
   ```

The GitHub credential used for `gh release create` must have **Contents: write** permission. If a release already exists, use `gh release upload ... --clobber`.

The updater checks the latest stable release, requires the ZIP's `.sha256` sidecar, verifies the bundle identifier and UULabs Team ID (`V726L7NR7H`), and asks before installing.
