#!/usr/bin/env bash
# End-to-end snapping check on a CI Mac: opens two Chrome windows, TextEdit and Finder,
# then asks the built app to snap them and verifies every window reached its slot.
set -uo pipefail

app="$1"
work="${RUNNER_TEMP:-/tmp}/snap-e2e"
mkdir -p "$work"
chrome_flags=(--user-data-dir="$work/chrome" --no-first-run --no-default-browser-check --disable-features=ChromeWhatsNewUI)

open -na "Google Chrome" --args "${chrome_flags[@]}" --new-window "data:text/html,<title>Research</title><h1>Research</h1>"
sleep 8
open -na "Google Chrome" --args "${chrome_flags[@]}" --new-window "data:text/html,<title>Inbox</title><h1>Inbox</h1>"
printf 'Snap check\n' > "$work/notes.txt"
open -a TextEdit "$work/notes.txt"
open -a Finder "$HOME"
sleep 8

status=0
run_check() {
    local name="$1"; shift
    local output="$work/$name.txt"
    rm -f "$output"
    open -W -n "$app" --args --snap-check "$@" --output "$output"
    printf '\n== %s ==\n' "$name"
    cat "$output" 2>/dev/null || echo "no output"
    screencapture -x "$work/$name.png" 2>/dev/null || true
    if grep -q '^SKIP' "$output" 2>/dev/null; then
        echo "::warning::Snap check $name skipped: $(grep '^SKIP' "$output")"
    elif ! grep -q '^PASS' "$output" 2>/dev/null; then
        echo "::error::Snap check $name failed"
        status=1
    fi
}

run_check grid grid
run_check grid-reversed-enhanced grid --reverse --force-enhanced-ui
run_check halves-enhanced halves --force-enhanced-ui
exit $status
