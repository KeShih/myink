#!/bin/bash
# End-to-end smoke test of Myink's automation hooks (open with, myink:// URLs, AppleScript) against
# the installed, running app — run `make run` first. Clears the shelf and restores it at the end.
# Note: the first osascript call may trigger a one-time Automation permission prompt for your
# terminal (System Settings > Privacy & Security > Automation); allow it and re-run if it timed out.
# Usage: scripts/verify-hooks.sh     (TIMEOUT=<seconds> to change the per-step wait, default 5)
set -euo pipefail

BUNDLE_ID=dev.keshi.myink
TIMEOUT="${TIMEOUT:-5}"
failures=0

osascript -e "application id \"$BUNDLE_ID\" is running" | grep -q true \
    || { echo "error: Myink ($BUNDLE_ID) isn't running — run 'make run' first" >&2; exit 1; }

# Temp files live in $HOME (files from /tmp are copied onto the shelf, home files are referenced).
WORK="$(mktemp -d "$HOME/myink-verify.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FILE1="$WORK/verify-open.txt"
FILE2="$WORK/verify-applescript.txt"
FILE3="$WORK/verify-url-path.txt"
for f in "$FILE1" "$FILE2" "$FILE3"; do echo "Myink verify-hooks $(date)" >"$f"; done

count() { osascript -e "tell application id \"$BUNDLE_ID\" to get item count"; }

# wait_for <expected count>: polls up to $TIMEOUT seconds.
wait_for() {
    local expected=$1 current deadline=$((SECONDS + TIMEOUT))
    while :; do
        current="$(count 2>/dev/null || echo '?')"
        [ "$current" = "$expected" ] && return 0
        if ((SECONDS >= deadline)); then
            echo "      item count is $current, expected $expected"
            return 1
        fi
        sleep 0.25
    done
}

# step <name> <expected count> <command...>
step() {
    local name=$1 expected=$2
    shift 2
    if "$@" >/dev/null && wait_for "$expected"; then
        echo "PASS  $name"
    else
        echo "FAIL  $name"
        failures=$((failures + 1))
    fi
    total=$expected
}

total="$(count)"
echo "==> baseline item count: $total"

step "open -b (file in \$HOME)" $((total + 1)) open -g -b "$BUNDLE_ID" "$FILE1"
step "myink://add?text=" $((total + 1)) open -g "myink://add?text=hello%20from%20verify"
step "myink://add?url=&title=" $((total + 1)) open -g "myink://add?url=https%3A%2F%2Fexample.com&title=Example"
step "myink://add?path=" $((total + 1)) open -g "myink://add?path=$FILE3"
step "AppleScript add POSIX file" $((total + 1)) \
    osascript -e "tell application id \"$BUNDLE_ID\" to add POSIX file \"$FILE2\""
step "AppleScript add text" $((total + 1)) \
    osascript -e "tell application id \"$BUNDLE_ID\" to add \"hello from AppleScript\""

filled=$total
step "myink://clear?all=1" 0 open -g "myink://clear?all=1"
step "myink://restore" "$filled" open -g "myink://restore"

if ((failures > 0)); then
    echo "==> $failures step(s) failed"
    exit 1
fi
echo "==> all hooks work"
