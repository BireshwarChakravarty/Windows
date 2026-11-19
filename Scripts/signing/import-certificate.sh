#!/usr/bin/env bash
# Imports a signing .p12 into a temporary keychain on a CI Mac and prints shell exports for
# SIGNING_IDENTITY and SIGNING_KEYCHAIN, for use with: eval "$(import-certificate.sh p12 password)"
set -euo pipefail

p12="$1"
password="$2"
keychain="${RUNNER_TEMP:-/tmp}/windows-signing-$$.keychain-db"
keychain_password="$(uuidgen)"

{
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
    # Add to the search list so codesign can use the private key.
    existing=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/" *$//')
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$keychain" $existing
    security find-identity -p codesigning "$keychain"
} >&2

# The identity's SHA-1 hash works whether or not the self-signed certificate is trusted.
identity=$(security find-identity -p codesigning "$keychain" | awk '/[0-9A-F]{40}/ { print $2; exit }')
if [[ -z "$identity" ]]; then
    echo "No code signing identity found in $p12" >&2
    exit 1
fi
printf 'export SIGNING_IDENTITY=%q SIGNING_KEYCHAIN=%q\n' "$identity" "$keychain"
