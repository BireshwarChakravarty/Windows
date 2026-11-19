#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
    printf '%s\n' 'Building Windows requires macOS 26 or later and Xcode 26 or later.' >&2
    exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcodebuild \
    -project "$repo_dir/Windows.xcodeproj" \
    -scheme Windows \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$repo_dir/.build/xcode" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$repo_dir/dist" \
    build

app="$repo_dir/dist/Windows.app"
archive="$repo_dir/dist/Windows-macOS26.zip"
disk_image="$repo_dir/dist/Windows-macOS26.dmg"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/Windows" -verify_arch arm64 x86_64
ditto -c -k --keepParent "$app" "$archive"

# A drag-to-install disk image with the app next to a link to Applications.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Windows.app"
ln -s /Applications "$staging/Applications"
rm -f "$disk_image"
for attempt in 1 2 3; do
    if hdiutil create -volname Windows -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$disk_image"; then
        break
    fi
    printf 'hdiutil create failed (attempt %s), retrying\n' "$attempt" >&2
    sleep 5
done
hdiutil verify "$disk_image"

printf '\nBuilt %s\nPackaged %s\nPackaged %s\n' "$app" "$archive" "$disk_image"
