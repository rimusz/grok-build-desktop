#!/usr/bin/env bash
set -euo pipefail

# Build a lightweight GrokBuild.app bundle for local development.
# Uses the same bundle identifier as the packaged app so Accessibility
# entries from System Settings apply to `make run` launches.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GrokBuild"
EXECUTABLE_NAME="GrokBuild"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_DIR="$ROOT_DIR/.build"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
BINARY_DIR="$BUILD_DIR/$BUILD_CONFIG"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

if [ ! -x "$BINARY_DIR/$EXECUTABLE_NAME" ]; then
    echo "Missing $BUILD_CONFIG binary at $BINARY_DIR/$EXECUTABLE_NAME. Run 'make build' or 'make build-debug' first." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [ -f "$BINARY_DIR/GrokBuildComputerUseMCP" ]; then
    cp "$BINARY_DIR/GrokBuildComputerUseMCP" "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
    chmod +x "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
fi

if [ -f "$ROOT_DIR/scripts/grokbuild-browser-mcp" ]; then
    cp "$ROOT_DIR/scripts/grokbuild-browser-mcp" "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
    chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
fi

if [ -f "$ROOT_DIR/scripts/grokbuild-install-update.sh" ]; then
    cp "$ROOT_DIR/scripts/grokbuild-install-update.sh" "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
    chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
fi

if [ -d "$ROOT_DIR/GrokBuild/Resources/Skills" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Skills"
    cp -R "$ROOT_DIR/GrokBuild/Resources/Skills/." "$APP_BUNDLE/Contents/Resources/Skills/"
fi

# Copy the Grok brand mark so GrokBrandIcon.mark() resolves it in the dev bundle
# (menu bar icon + welcome state). Without this the app falls back to an SF Symbol.
ICONSET_DIR="$ROOT_DIR/GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset"
for icon in MenuBarIcon.png MenuBarIcon@2x.png MenuBarIcon@3x.png; do
    if [ -f "$ICONSET_DIR/$icon" ]; then
        cp "$ICONSET_DIR/$icon" "$APP_BUNDLE/Contents/Resources/$icon"
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/bundle-agent-desktop.sh" "$SCRIPT_DIR/codesign-app-bundle.sh"
"$SCRIPT_DIR/bundle-agent-desktop.sh" "$APP_BUNDLE/Contents/MacOS" || true

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.grokbuild.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>GrokBuild uses the microphone for voice input in the chat composer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>GrokBuild transcribes your speech to text for chat messages.</string>
</dict>
</plist>
EOF

"$SCRIPT_DIR/codesign-app-bundle.sh" "$APP_BUNDLE"
echo "Dev app ready: $APP_BUNDLE"
