#!/bin/bash
# Builds build/AppIcon.icns from Resources/AppIcon-1024.png (rendering the master first if missing).
# Usage: scripts/make-icon.sh [--force]   (--force re-renders the master PNG)
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER=Resources/AppIcon-1024.png
OUT=build/AppIcon.icns
ICONSET=build/AppIcon.iconset

if [ ! -f "$MASTER" ] || [ "${1:-}" = "--force" ]; then
    swift scripts/render-icon.swift "$MASTER"
fi
if [ -f "$OUT" ] && [ "$OUT" -nt "$MASTER" ]; then
    exit 0
fi

mkdir -p build
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"
echo "wrote $OUT"
