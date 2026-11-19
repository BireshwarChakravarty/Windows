#!/usr/bin/env bash
# End-to-end snapping check on a CI Mac: opens two Chrome windows, TextEdit and Finder,
# then asks the built app to snap them and verifies every window reached its slot.
set -uo pipefail

app="$1"
work="${RUNNER_TEMP:-/tmp}/snap-e2e"
mkdir -p "$work"
# Every step gets a time limit so one stuck command cannot hang the job.
with_timeout() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
chrome_flags=(--user-data-dir="$work/chrome" --no-first-run --no-default-browser-check
    --use-mock-keychain --password-store=basic --disable-features=ChromeWhatsNewUI)

with_timeout 120 swift "$(dirname "$0")/set-resolution.swift" || echo "Couldn't change the display mode"
sleep 3

echo "Opening test windows"
# Launch Chrome directly: going through open(1) waits on first-run work and can hang on CI.
"$chrome" "${chrome_flags[@]}" --new-window "data:text/html,<title>Research</title><h1>Research</h1>" >"$work/chrome.log" 2>&1 &
sleep 10
"$chrome" "${chrome_flags[@]}" --new-window "data:text/html,<title>Inbox</title><h1>Inbox</h1>" >>"$work/chrome.log" 2>&1 &
printf 'Snap check\n' > "$work/notes.txt"
with_timeout 30 open -a TextEdit "$work/notes.txt"
with_timeout 30 open -a Finder "$HOME"
sleep 12

status=0
run_check() {
    local name="$1"; shift
    local output="$work/$name.txt"
    rm -f "$output"
    printf '\n== %s ==\n' "$name"
    with_timeout 120 open -W -n "$app" --args --snap-check "$@" --output "$output" \
        || echo "The check did not finish within 120 s"
    pkill -f "$app/Contents/MacOS/" 2>/dev/null || true
    cat "$output" 2>/dev/null || echo "no output"
    with_timeout 10 screencapture -x "$work/$name.png" 2>/dev/null || true
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

printf '\n== Activity log ==\n'
cp "$HOME/Library/Logs/Windows/Windows.log" "$work/" 2>/dev/null && cat "$work/Windows.log" || echo "no activity log"
exit $status
