#!/usr/bin/env bash
# Sign GrokBuild.app so nested tools share com.grokbuild.app for Accessibility.
# Usage: codesign-app-bundle.sh /path/to/GrokBuild.app [signing_identity]

set -euo pipefail

APP_BUNDLE="${1:?app bundle path required}"
IDENTITY="${2:--}"
BUNDLE_ID="com.grokbuild.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/GrokBuild.entitlements"

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: Missing entitlements file: $ENTITLEMENTS" >&2
    exit 1
fi

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

sign_nested() {
    local name="$1"
    local path="$MACOS_DIR/$name"
    [ -f "$path" ] || return 0
    echo "==> Signing $name as $BUNDLE_ID"
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$path"
}

sign_nested "GrokBuild"
sign_nested "GrokBuildComputerUseMCP"
sign_nested "agent-desktop"

if [ "$IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing app bundle (required for macOS Accessibility trust)"
    # Embed the same entitlements as release so local packages match what notarized
    # builds ship (Voice control needs device.audio-input under Hardened Runtime).
    codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_BUNDLE"
else
    echo "==> Signing app bundle with identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE"
fi
