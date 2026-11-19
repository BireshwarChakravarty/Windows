#!/usr/bin/env bash
# One-time setup, run on your Mac. Creates a code signing certificate for Windows and saves it as
# GitHub Actions secrets, so every build has the same identity and macOS keeps the Accessibility
# permission when you update. The certificate stays in ~/Library/Application Support/Windows Signing.
#
#   curl -fsSL https://raw.githubusercontent.com/BireshwarChakravarty/Windows/main/Scripts/signing/setup-github-signing.sh | bash
set -euo pipefail

repo="${WINDOWS_REPO:-BireshwarChakravarty/Windows}"
store="$HOME/Library/Application Support/Windows Signing"
raw="https://raw.githubusercontent.com/$repo/main/Scripts/signing"

if [[ -f "$store/signing.p12" && -f "$store/password.txt" ]]; then
    echo "Using the existing certificate in $store"
else
    here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    if [[ -x "$here/make-certificate.sh" ]]; then
        "$here/make-certificate.sh" "$store"
    else
        curl -fsSL "$raw/make-certificate.sh" | bash -s -- "$store"
    fi
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    base64 -i "$store/signing.p12" | gh secret set SIGNING_CERT_P12 --repo "$repo"
    gh secret set SIGNING_CERT_PASSWORD --repo "$repo" < "$store/password.txt"
    echo "Saved both secrets to $repo."
else
    page="https://github.com/$repo/settings/secrets/actions/new"
    echo
    echo "Add two repository secrets on GitHub (the GitHub CLI isn't set up, so this is done by hand)."
    base64 -i "$store/signing.p12" | pbcopy
    echo "1. The certificate is now on your clipboard. On the page that opens, name the secret"
    echo "   SIGNING_CERT_P12, paste, and click Add secret."
    open "$page"
    read -r -p "   Press Return when it's saved. " _ < /dev/tty
    pbcopy < "$store/password.txt"
    echo "2. The password is now on your clipboard. Click New repository secret, name it"
    echo "   SIGNING_CERT_PASSWORD, paste, and click Add secret."
    open "$page"
    read -r -p "   Press Return when it's saved. " _ < /dev/tty
    printf '' | pbcopy
    echo "Done. Clipboard cleared."
fi
echo "Keep $store safe: a new certificate means allowing Windows in Accessibility once more."
