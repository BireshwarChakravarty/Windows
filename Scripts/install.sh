#!/usr/bin/env bash
# Fresh install of Windows on this Mac:
#   curl -fsSL https://raw.githubusercontent.com/BireshwarChakravarty/Windows/main/Scripts/install.sh | bash
# Quits any running copy, removes the old app and its Accessibility entry, installs the latest release
# into /Applications, and opens it. Add "-s -- --clean" after bash to also remove saved layouts and logs.
set -euo pipefail

repo="BireshwarChakravarty/Windows"
bundle_id="com.bireshwarchakravarty.Windows"
url="https://github.com/$repo/releases/latest/download/Windows-macOS26.dmg"
app="/Applications/Windows.app"
clean=false
[[ "${1:-}" == "--clean" ]] && clean=true

work="$(mktemp -d)"
mount="$work/volume"
cleanup() { hdiutil detach -quiet "$mount" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

echo "→ Downloading the latest Windows"
curl -fL --progress-bar -o "$work/Windows.dmg" "$url"

echo "→ Quitting any running copy"
if pkill -f "/Windows.app/Contents/MacOS/Windows" 2>/dev/null; then sleep 1; fi

echo "→ Removing the old app and its Accessibility entry"
rm -rf "$app"
tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1 || true
if $clean; then
    echo "→ Removing saved layouts and logs"
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Logs/Windows"
fi

echo "→ Installing to /Applications"
mkdir -p "$mount"
hdiutil attach -nobrowse -quiet -mountpoint "$mount" "$work/Windows.dmg"
ditto "$mount/Windows.app" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

version=$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "→ Opening Windows $version"
open "$app"

cat <<'NEXT'

Installed. One step left, which macOS only lets you do yourself:
  When asked, click Open System Settings, then switch on Windows under
  Privacy & Security → Accessibility. The Windows panel notices within a second.
NEXT
