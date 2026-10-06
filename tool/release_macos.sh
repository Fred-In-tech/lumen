#!/usr/bin/env bash
# Builds the macOS app and zips it for a GitHub release.
#
#   bash tool/release_macos.sh            # build + zip into dist/
#   bash tool/release_macos.sh --publish  # also create the GitHub release
#
# The zip is ad-hoc signed (no Developer ID), so install.sh clears the
# Gatekeeper quarantine flag after download. Publishing needs `gh` signed in
# to an account that can write to $LUMEN_REPO (default Fred-In-tech/lumen).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${LUMEN_REPO:-Fred-In-tech/lumen}"
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' app/pubspec.yaml)
TAG="v$VERSION"
# Flutter release builds are universal (arm64 + x86_64).
ARCH=universal
ZIP="dist/Lumen-macos-$ARCH-$TAG.zip"

echo "== build $TAG ($ARCH)"
(cd app && flutter build macos --release)
APP="app/build/macos/Build/Products/Release/lumen.app"
test -d "$APP"
lipo -archs "$APP/Contents/MacOS/lumen"

echo "== zip"
mkdir -p dist
rm -f "$ZIP"
# ditto keeps the bundle's resource forks and code signature intact.
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
du -h "$ZIP"

if [[ "${1:-}" == "--publish" ]]; then
  echo "== publish $TAG to $REPO"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" "$ZIP.sha256" --repo "$REPO" --clobber
  else
    gh release create "$TAG" "$ZIP" "$ZIP.sha256" --repo "$REPO" \
      --title "Lumen $TAG (macOS)" \
      --notes "macOS build ($ARCH). Install with the one-line command in README.md."
  fi
fi
