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
#
# It also installs an auto-updater (a per-user LaunchAgent) that checks
# GitHub at login and every 6 hours and installs a newer release when Lumen
# is not open. Modes:
#   install.sh              install or reinstall now, set up auto-update
#   install.sh --update     only install if a newer release exists (quiet)
#   install.sh --uninstall  remove Lumen's app and the auto-updater
set -euo pipefail

MODE="${1:-install}"
SUPPORT="$HOME/Library/Application Support/Lumen"
AGENT_ID="com.fvm.lumen.updater"
AGENT="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

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

if [[ "$MODE" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null || true
  rm -f "$AGENT"
  rm -rf "$SUPPORT/updater"
  osascript -e 'tell application "lumen" to quit' >/dev/null 2>&1 || true
  rm -rf "$DEST/$APP_NAME"
  echo "Lumen and its auto-updater are removed. Your photos library is kept"
  echo "in ~/Library/Containers/com.fvm.lumen (delete it to remove everything)."
  exit 0
fi

auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

echo "Looking up the latest Lumen release in $REPO…"
release=$(curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" "$API") || {
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

installed=$(defaults read "$DEST/$APP_NAME/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
if [[ "$MODE" == "--update" ]]; then
  # Newer only (sort -V orders version numbers), and never under the user.
  if [[ -n "$installed" ]]; then
    newest=$(printf '%s\n%s\n' "$installed" "${tag#v}" | sort -V | tail -1)
    if [[ "$newest" == "$installed" ]]; then
      echo "Lumen $installed is up to date."
      exit 0
    fi
  fi
  if pgrep -xq lumen; then
    echo "Lumen ${tag#v} is available; it installs the next time Lumen is closed."
    exit 0
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Lumen $tag…"
curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: application/octet-stream" -o "$tmp/lumen.zip" "$asset_url"

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

# Auto-update: keep a copy of this script and run it at login and every
# 6 hours. A token, if one was used, is stored readable by this user only.
install_updater() {
  mkdir -p "$SUPPORT/updater" "$HOME/Library/LaunchAgents"
  curl -fsSL ${auth[@]+"${auth[@]}"} \
    "https://raw.githubusercontent.com/$REPO/main/install.sh" \
    -o "$SUPPORT/updater/install.sh"
  chmod 700 "$SUPPORT/updater/install.sh"
  : > "$SUPPORT/updater/env"
  chmod 600 "$SUPPORT/updater/env"
  {
    printf 'export LUMEN_REPO=%q\n' "$REPO"
    printf 'export LUMEN_INSTALL_DIR=%q\n' "$DEST"
    [[ -n "${GITHUB_TOKEN:-}" ]] && printf 'export GITHUB_TOKEN=%q\n' "$GITHUB_TOKEN"
  } > "$SUPPORT/updater/env"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>source "\$HOME/Library/Application Support/Lumen/updater/env"; /bin/bash "\$HOME/Library/Application Support/Lumen/updater/install.sh" --update</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
  <key>StandardOutPath</key><string>$SUPPORT/updater/update.log</string>
  <key>StandardErrorPath</key><string>$SUPPORT/updater/update.log</string>
</dict>
</plist>
PLIST
  # Under launchd (--update) the agent is this very process: re-loading it
  # would stop the update half-way, and the new plist is read next login.
  if [[ "$MODE" != "--update" ]]; then
    launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
  fi
}

echo
if [[ "$MODE" == "--update" ]]; then
  # Refresh the updater itself so fixes to this script reach testers too.
  install_updater
  echo "Lumen updated to $tag."
  exit 0
fi
install_updater
echo "Lumen $tag is installed, with automatic updates. Opening it now."
open "$DEST/$APP_NAME"
