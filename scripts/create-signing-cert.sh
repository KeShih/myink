#!/bin/bash
# Creates a self-signed code-signing identity for local Myink builds so that macOS privacy grants
# (Files & Folders, drag-and-drop file access, the login item) survive rebuilds. Ad-hoc signatures pin
# the code hash, which changes with every build.
#
# The identity lives in its own keychain (~/Library/Keychains/myink-signing.keychain-db) protected by a
# random password stored in ~/.config/myink (mode 600). Nothing is added to the login keychain and no
# key material is written into the repository.
#
# Usage: scripts/create-signing-cert.sh [--remove]
set -euo pipefail

NAME="Myink Local Signing"
CONF_DIR="$HOME/.config/myink"
KEYCHAIN="$HOME/Library/Keychains/myink-signing.keychain-db"
OPENSSL=/usr/bin/openssl

if [ "${1:-}" = "--remove" ]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null || rm -f "$KEYCHAIN"
    rm -f "$CONF_DIR/signing-identity" "$CONF_DIR/keychain-password"
    echo "==> removed $KEYCHAIN"
    exit 0
fi

if [ -f "$KEYCHAIN" ] && [ -f "$CONF_DIR/signing-identity" ]; then
    echo "==> signing identity already exists: $(cat "$CONF_DIR/signing-identity") ($NAME)"
    exit 0
fi

mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> generating certificate"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PASSWORD="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

echo "==> creating keychain $KEYCHAIN"
KEYCHAIN_PASSWORD="$("$OPENSSL" rand -hex 24)"
rm -f "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

printf '%s' "$KEYCHAIN_PASSWORD" > "$CONF_DIR/keychain-password"
chmod 600 "$CONF_DIR/keychain-password"
FINGERPRINT="$("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
printf '%s' "$FINGERPRINT" > "$CONF_DIR/signing-identity"

echo "==> created \"$NAME\" ($FINGERPRINT)"
echo "    builds are now signed with it automatically (scripts/bundle.sh)"
