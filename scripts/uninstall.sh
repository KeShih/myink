#!/bin/bash
# Removes the installed Myink.app, its Launch Services registration, the PDF Services alias and the
# CLI symlink. Shelf data in ~/Library/Application Support/Myink is kept unless --purge is given.
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST="$INSTALL_DIR/Myink.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if pgrep -xq Myink; then
    pkill -TERM -x Myink || true
    for _ in $(seq 1 50); do pgrep -xq Myink || break; sleep 0.1; done
fi
[ -d "$DEST" ] && "$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
rm -rf "$DEST"
rm -f "$HOME/Library/PDF Services/Save PDF to Myink"
if [ -L "$HOME/.local/bin/myink" ]; then rm -f "$HOME/.local/bin/myink"; fi
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

if [ "${1:-}" = "--purge" ]; then
    rm -rf "$HOME/Library/Application Support/Myink" "$HOME/Library/Caches/dev.keshi.myink"
    defaults delete dev.keshi.myink >/dev/null 2>&1 || true
    echo "==> removed Myink and its data"
else
    echo "==> removed Myink (shelf data kept; use --purge to delete it)"
fi
