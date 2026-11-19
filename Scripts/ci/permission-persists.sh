#!/usr/bin/env bash
# Checks on a CI Mac that the Accessibility permission survives an update when builds are signed with
# the same certificate, and (as a control) that an ad hoc signed build is not trusted.
set -euo pipefail

app="$1"
here="$(cd "$(dirname "$0")" && pwd)"
work="${RUNNER_TEMP:-/tmp}/permission"
rm -rf "$work"
mkdir -p "$work"
with_timeout() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }

"$here/../signing/make-certificate.sh" "$work/certificate" "Windows CI Test Signing"
eval "$("$here/../signing/import-certificate.sh" "$work/certificate/signing.p12" "$(cat "$work/certificate/password.txt")")"

build() {   # build <name> <build number> <identity>
    local copy="$work/$1/Windows.app"
    mkdir -p "$work/$1"
    ditto "$app" "$copy"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $2" "$copy/Contents/Info.plist"
    if [[ "$3" == "-" ]]; then
        codesign --force --options runtime --sign - "$copy"
    else
        codesign --force --options runtime --timestamp=none --keychain "$SIGNING_KEYCHAIN" --sign "$3" "$copy"
    fi
    codesign --verify --strict "$copy"
    printf '%s: %s\n' "$1" "$(codesign --display --requirements - "$copy" 2>&1 | grep designated)"
}

trust() {   # trust <name> -> prints TRUSTED or NOT TRUSTED
    local output="$work/$1.txt"
    rm -f "$output"
    with_timeout 60 open -W -n "$work/$1/Windows.app" --args --trust-check --output "$output" || true
    cat "$output" 2>/dev/null || echo "NO RESULT"
}

build first 100 "$SIGNING_IDENTITY"
build update 101 "$SIGNING_IDENTITY"
build adhoc 102 -

# Allow only the first build, the way System Settings records it, then try the others.
sudo python3 "$here/grant-accessibility.py" --remove "$work/first/Windows.app"
sudo python3 "$here/grant-accessibility.py" --requirement-of "$work/first/Windows.app"
sudo killall tccd 2>/dev/null || true
sleep 2

status=0
first=$(trust first);   echo "First build:            $first"
update=$(trust update); echo "Update, same cert:      $update"
adhoc=$(trust adhoc);   echo "Ad hoc build (control): $adhoc"
[[ "$first" == TRUSTED* ]] || { echo "::error::The allowed build itself is not trusted"; status=1; }
[[ "$update" == TRUSTED* ]] || { echo "::error::An update signed with the same certificate lost Accessibility access"; status=1; }
[[ "$adhoc" == "NOT TRUSTED"* ]] || { echo "::error::The control build was trusted, so this check proves nothing"; status=1; }

sudo python3 "$here/grant-accessibility.py" --remove "$work/first/Windows.app"
security delete-keychain "$SIGNING_KEYCHAIN" 2>/dev/null || true
exit $status
