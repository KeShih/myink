#!/bin/bash
# Installs build/Myink.app as the single copy in $INSTALL_DIR (default ~/Applications), registers it
# with Launch Services (URL scheme, document types, Services) and launches it.
# Usage: scripts/install.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SRC=build/Myink.app
DEST="$INSTALL_DIR/Myink.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$SRC" ] || { echo "error: $SRC not found — run scripts/bundle.sh first" >&2; exit 1; }

# Quit a running copy gracefully: Myink flushes its shelf on SIGTERM.
if pgrep -xq Myink; then
    echo "==> quitting running Myink"
    pkill -TERM -x Myink || true
    for _ in $(seq 1 50); do pgrep -xq Myink || break; sleep 0.1; done
    pkill -KILL -x Myink 2>/dev/null || true
fi

echo "==> installing to $DEST"
mkdir -p "$INSTALL_DIR"
rm -rf "$DEST"
ditto "$SRC" "$DEST"

"$LSREGISTER" -u "$PWD/$SRC" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$DEST"
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

if [ "${1:-}" != "--no-open" ]; then
    open "$DEST"
    echo "==> launched $DEST"
fi
