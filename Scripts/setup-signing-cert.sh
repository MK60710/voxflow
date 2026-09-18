#!/bin/bash
# One-time setup: create and trust the self-signed "VoxFlow Dev" code-signing
# certificate that Scripts/bundle.sh signs every build with.
#
# WHY a real (if self-signed) cert instead of ad-hoc signing: ad-hoc signing
# changes the app's identity (designated requirement = CDHash) on every
# rebuild, which silently revokes the Accessibility/Microphone TCC grants
# every time you rebuild. A stable, named certificate keeps the app's
# identity constant across rebuilds, so a grant made once survives.
#
# This script is idempotent: if "VoxFlow Dev" already exists in your login
# keychain, it does nothing rather than risk creating a second certificate
# with the same name (which would make `codesign --sign "VoxFlow Dev"`
# ambiguous about which one to use).
set -euo pipefail

CERT_NAME="VoxFlow Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$CERT_NAME\" already exists in your login keychain — nothing to do."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Generating a self-signed RSA-2048 code-signing certificate named \"$CERT_NAME\" (10-year validity)…"
openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CERT_NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature"

echo "Importing into your login keychain…"
security import "$WORKDIR/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$WORKDIR/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign

echo "Trusting it for code signing (you'll likely be prompted for your login password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo "Done. \"$CERT_NAME\" is ready — Scripts/bundle.sh can now sign builds with it."
