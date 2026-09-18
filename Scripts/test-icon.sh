#!/bin/bash
# Verifies the app icon packaging/wiring (not the artwork itself — see
# tdd-and-fixing's generated-code exception, ledger .claude-state/app-icon):
# 1. Resources/AppIcon.icns exists and unpacks to all 10 sizes macOS expects.
# 2. Scripts/bundle.sh embeds it correctly (CFBundleIconFile in Info.plist,
#    the .icns copied into Contents/Resources/).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail=0
pass() { echo "PASS: $1"; }
failed() { echo "FAIL: $1"; fail=1; }

ICNS="Resources/AppIcon.icns"
EXPECTED_SIZES="icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png"

if [ ! -f "$ICNS" ]; then
    failed "$ICNS does not exist"
else
    pass "$ICNS exists"

    TMP_ICONSET=$(mktemp -d)/AppIcon.iconset
    if iconutil -c iconset "$ICNS" -o "$TMP_ICONSET" 2>/dev/null; then
        pass "iconutil can unpack $ICNS"
        missing=""
        for size in $EXPECTED_SIZES; do
            if [ ! -f "$TMP_ICONSET/$size" ]; then
                missing="$missing $size"
            fi
        done
        if [ -z "$missing" ]; then
            pass "all 10 expected icon sizes present"
        else
            failed "missing icon sizes:$missing"
        fi
    else
        failed "iconutil could not unpack $ICNS"
    fi
fi

APP="./.build/VoxFlow.app"
if [ ! -d "$APP" ]; then
    failed "$APP does not exist (run Scripts/bundle.sh first)"
else
    if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
        pass "AppIcon.icns is present in the bundled app's Resources"
    else
        failed "AppIcon.icns missing from $APP/Contents/Resources"
    fi

    if /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
        ICON_KEY=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist")
        if [ "$ICON_KEY" = "AppIcon" ]; then
            pass "Info.plist's CFBundleIconFile is AppIcon"
        else
            failed "Info.plist's CFBundleIconFile is '$ICON_KEY', expected 'AppIcon'"
        fi
    else
        failed "Info.plist has no CFBundleIconFile key"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "All icon checks passed."
    exit 0
else
    echo "Icon checks failed."
    exit 1
fi
