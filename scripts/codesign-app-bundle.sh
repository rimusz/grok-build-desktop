#!/usr/bin/env bash
# Sign GrokBuild.app so nested tools share com.grokbuild.app for Accessibility.
# Usage: codesign-app-bundle.sh /path/to/GrokBuild.app [signing_identity]

set -euo pipefail

APP_BUNDLE="${1:?app bundle path required}"
IDENTITY="${2:--}"
BUNDLE_ID="com.grokbuild.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

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
    codesign --force --sign - --timestamp=none "$APP_BUNDLE"
else
    echo "==> Signing app bundle with identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" \
        --options runtime \
        --entitlements /dev/stdin <<'ENTITLEMENTS' "$APP_BUNDLE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
fi
