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
codesign --verify --strict "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/Windows"
ditto -c -k --keepParent "$app" "$archive"

printf '\nBuilt %s\nPackaged %s\n' "$app" "$archive"
