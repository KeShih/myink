#!/bin/bash
# Compiles Myink with SwiftPM and assembles a signed build/Myink.app (no Xcode required).
# Usage: scripts/bundle.sh [debug|release]
# Signing: uses $SIGN_IDENTITY if set, else the identity created by `make cert`, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP=build/Myink.app
CONTENTS="$APP/Contents"
CONF_DIR="$HOME/.config/myink"
KEYCHAIN="$HOME/Library/Keychains/myink-signing.keychain-db"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product Myink
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
mkdir -p build
touch build/.metadata_never_index # keep Spotlight/LaunchServices away from the staging copy
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Myink" "$CONTENTS/MacOS/Myink"
cp Resources/Info.plist "$CONTENTS/Info.plist"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0).$(date +%s)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
plutil -lint -s "$CONTENTS/Info.plist"
cp Resources/Myink.sdef "$CONTENTS/Resources/Myink.sdef"
scripts/make-icon.sh
cp build/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp scripts/myink "$CONTENTS/Resources/myink"
chmod +x "$CONTENTS/Resources/myink"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Swift back-deployment libraries (only needed if the deployment target predates the running OS's Swift runtime).
RPATH_LIBS="$(otool -L "$CONTENTS/MacOS/Myink" | awk '/@rpath\/libswift/ {sub("@rpath/", "", $1); print $1}')"
if [ -n "$RPATH_LIBS" ]; then
    SWIFT_LIB_DIR="$(xcode-select -p)/usr/lib/swift-6.2/macosx"
    mkdir -p "$CONTENTS/Frameworks"
    for lib in $RPATH_LIBS; do
        echo "    embedding $lib"
        cp "$SWIFT_LIB_DIR/$lib" "$CONTENTS/Frameworks/$lib"
    done
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/Myink" 2>/dev/null || true
fi

echo "==> signing"
KEYCHAIN_ARGS=()
if [ -n "${SIGN_IDENTITY:-}" ]; then
    IDENTITY="$SIGN_IDENTITY"
elif [ -f "$CONF_DIR/signing-identity" ] && [ -f "$KEYCHAIN" ]; then
    IDENTITY="$(cat "$CONF_DIR/signing-identity")"
    security unlock-keychain -p "$(cat "$CONF_DIR/keychain-password")" "$KEYCHAIN"
    KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
else
    IDENTITY="-"
    echo "    warning: ad-hoc signature — privacy grants reset on every build. Run 'make cert' once to fix."
fi
xattr -cr "$APP"
if [ -d "$CONTENTS/Frameworks" ]; then
    for lib in "$CONTENTS"/Frameworks/*.dylib; do
        codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --timestamp=none "$lib"
    done
fi
codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "    $(codesign -d -r- "$APP" 2>&1 | grep designated)"
echo "==> built $APP ($BUILD_NUMBER)"
