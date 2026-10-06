#!/usr/bin/env bash
# Installs the latest Lumen macOS build from GitHub into /Applications.
#
#   GITHUB_TOKEN=<token> bash -c "$(curl -fsSL -H 'Authorization: Bearer <token>' \
#     https://raw.githubusercontent.com/Fred-In-tech/lumen/main/install.sh)"
#
# The repository is private, so a GitHub token with read access to it is
# needed (a collaborator's fine-grained token with "Contents: read"). If the
# release is on a public repository, no token is needed:
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
#
# The app is not notarized by Apple yet, so the script removes the
# quarantine flag that would otherwise make macOS refuse to open it.
set -euo pipefail

REPO="${LUMEN_REPO:-Fred-In-tech/lumen}"
APP_NAME="lumen.app"
DEST="${LUMEN_INSTALL_DIR:-/Applications}"
API="https://api.github.com/repos/$REPO/releases/latest"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Lumen's installer only supports macOS for now." >&2
  exit 1
fi
ARCH=$(uname -m)
export LUMEN_ARCH="$ARCH"

auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

echo "Looking up the latest Lumen release in $REPO…"
release=$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "$API") || {
  echo "Could not read the release. For a private repository set GITHUB_TOKEN." >&2
  exit 1
}

# Pick the zip for this machine's architecture. JSON is parsed with the
# JavaScript runtime every Mac ships (python3 may prompt to install tools).
picked=$(printf '%s' "$release" | osascript -l JavaScript -e '
  ObjC.import("stdlib");
  var input = $.NSString.alloc.initWithDataEncoding($.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile, $.NSUTF8StringEncoding).js;
  var r = JSON.parse(input), arch = $.getenv("LUMEN_ARCH");
  var out = "";
  // A universal build serves every Mac; an arch-specific one is also accepted.
  ["universal", arch].some(function (want) {
    return (r.assets || []).some(function (a) {
      if (a.name.indexOf("Lumen-macos-" + want) === 0 && /\.zip$/.test(a.name)) { out = r.tag_name + " " + a.url; return true; }
    });
  });
  out;' 2>/dev/null) || picked=""
tag=${picked%% *}
asset_url=${picked#* }
[[ "$picked" == *" "* ]] || asset_url=""
if [[ -z "${asset_url:-}" ]]; then
  echo "No macOS build for $ARCH in the latest release." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Lumen $tag…"
curl -fsSL "${auth[@]}" -H "Accept: application/octet-stream" -o "$tmp/lumen.zip" "$asset_url"

echo "Installing to $DEST/$APP_NAME…"
ditto -x -k "$tmp/lumen.zip" "$tmp/unzipped"
app=$(find "$tmp/unzipped" -maxdepth 2 -name "$APP_NAME" | head -1)
test -n "$app"
if [[ -d "$DEST/$APP_NAME" ]]; then
  osascript -e "tell application \"lumen\" to quit" >/dev/null 2>&1 || true
  rm -rf "$DEST/$APP_NAME"
fi
ditto "$app" "$DEST/$APP_NAME"
# Not notarized yet: clear the quarantine flag so Gatekeeper lets it open.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

echo
echo "Lumen $tag is installed. Opening it now."
open "$DEST/$APP_NAME"
