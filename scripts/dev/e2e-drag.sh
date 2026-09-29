#!/bin/bash
# Real-drag end-to-end test: Finder → shelf → Finder, using HID events (moves the actual cursor).
# Run it while you're not using the Mac: it raises Finder, moves the pointer and steals focus.
# Needs: Myink installed and running (make run), Accessibility permission for this terminal.
# Usage: scripts/dev/e2e-drag.sh [rounds]
set -uo pipefail
cd "$(dirname "$0")/../.."

ROUNDS="${1:-1}"
E2E="$HOME/MyinkE2E"
TOOLS=/tmp/myink-e2e-tools
mkdir -p "$TOOLS"
for tool in hiddrag axfind axfront; do
    [ "$TOOLS/$tool" -nt "scripts/dev/$tool.swift" ] || swiftc -O -o "$TOOLS/$tool" "scripts/dev/$tool.swift" 2>/dev/null
done

FRONT=$(osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null || true)
count() { osascript -e 'tell application id "dev.keshi.myink" to get item count'; }
center() { read -r X Y W H < <("$TOOLS/axfind" com.apple.finder "$1") && echo "$((X + W / 2)) $((Y + H / 2))"; }
shelf_cell() { # center of the first shelf cell, in global points
    local line
    line=$(swift scripts/dev/windows.swift Myink 2>/dev/null | head -1)
    local x y w
    x=$(sed -E 's/.*x=([0-9-]+).*/\1/' <<<"$line"); y=$(sed -E 's/.* y=([0-9-]+).*/\1/' <<<"$line"); w=$(sed -E 's/.*w=([0-9]+).*/\1/' <<<"$line")
    echo "$((x + w / 2)) $((y + 32 + 50))"
}
wait_count() { for _ in $(seq 1 30); do [ "$(count)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

for round in $(seq 1 "$ROUNDS"); do
    echo "== round $round"
    rm -rf "$E2E"; mkdir -p "$E2E/dest"; echo alpha >"$E2E/alpha.txt"
    open -g "myink://clear?all=1"; wait_count 0
    open -g -a Finder "$E2E"; sleep 1
    "$TOOLS/axfront" com.apple.finder >/dev/null
    read -r AX AY < <(center alpha.txt)
    "$TOOLS/hiddrag" "$AX" "$AY" 64 560 --via 300,420 --steps 18 --hold-ms 600 --front com.apple.finder >/dev/null
    check "drag in from Finder adds the file" "wait_count 1"

    "$TOOLS/axfront" com.apple.finder >/dev/null
    read -r DX DY < <(center dest)
    read -r SX SY < <(shelf_cell)
    "$TOOLS/axfront" com.apple.finder >/dev/null
    "$TOOLS/hiddrag" "$SX" "$SY" "$DX" "$DY" --via 250,400 --steps 18 --hold-ms 700 >/dev/null
    check "drag out moves the file into the folder" "sleep 1; [ -f '$E2E/dest/alpha.txt' ] && [ ! -f '$E2E/alpha.txt' ]"
    check "the shelf is empty afterwards" "wait_count 0"

    open -g "myink://restore"
    check "restore brings the (moved) file back" "wait_count 1"
done

[ -n "$FRONT" ] && "$TOOLS/axfront" "$FRONT" >/dev/null
[ $fail = 0 ] && echo "==> e2e drag test passed" || { echo "==> e2e drag test FAILED"; exit 1; }
