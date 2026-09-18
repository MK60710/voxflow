#!/bin/bash
# Build VoxFlow and assemble a signed .app bundle.
# Signing uses the self-signed "VoxFlow Dev" identity so TCC permission
# grants survive rebuilds (ad-hoc signing would reset them every build).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP_DIR="$REPO_ROOT/.build/VoxFlow.app"
IDENTITY="VoxFlow Dev"

cd "$REPO_ROOT"
swift build -c "$CONFIG"

BIN="$REPO_ROOT/.build/$CONFIG/VoxFlow"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/VoxFlow"
cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoxFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.mihirk.voxflow</string>
    <key>CFBundleName</key>
    <string>VoxFlow</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxFlow records your voice while you hold the dictation hotkey, so it can transcribe what you say.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$IDENTITY" "$APP_DIR"
codesign --verify --deep "$APP_DIR"
echo "Bundled and signed: $APP_DIR"
