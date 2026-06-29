#!/usr/bin/env bash
set -euo pipefail

# Build GrokBuild macOS menu bar app from the command line.
# Uses Swift Package Manager (SPM) by default.
# Adapted from: https://github.com/Gitlawb/node/blob/main/scripts/build-macos-app.sh
#
# Usage:
#   ./scripts/build-macos-app.sh
#   ./scripts/build-macos-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
#
# Prerequisites:
#   - Xcode command line tools installed (xcode-select --install)
#   - Run `grok login` if you want to test the app with the real CLI
#
# Recommended for development: `swift build -c release`
# Use this script mainly for packaging .app + DMG (and signing).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

APP_NAME="GrokBuild"
EXECUTABLE_NAME="GrokBuild"
SCHEME="GrokBuild"
CONFIGURATION="Release"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"

SIGN_IDENTITY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --name)
            APP_NAME="$2"
            shift 2
            ;;

        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --sign IDENTITY    Codesign the resulting .app bundle"
            echo "  --name NAME        Override the app name (default: GrokBuild)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "==> Building ${APP_NAME} macOS app..."

# Ensure dist directory exists
mkdir -p "$DIST_DIR"
mkdir -p "$BUILD_DIR"

# === SPM-first path (recommended) ===
if [ -f "$ROOT_DIR/Package.swift" ]; then
    echo "==> Building with Swift Package Manager..."

    swift build -c release --package-path "$ROOT_DIR"

    # Assemble the .app bundle
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$BUILD_DIR/release/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
    if [ -f "$BUILD_DIR/release/GrokBuildComputerUseMCP" ]; then
        cp "$BUILD_DIR/release/GrokBuildComputerUseMCP" "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
        chmod +x "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
        echo "==> Copied Computer Use MCP helper"
    else
        echo "ERROR: Missing GrokBuildComputerUseMCP helper binary"
        exit 1
    fi
    if [ -f "$ROOT_DIR/scripts/grokbuild-browser-mcp" ]; then
        cp "$ROOT_DIR/scripts/grokbuild-browser-mcp" "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
        chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
        echo "==> Copied browser MCP bridge"
    fi
    if [ -f "$ROOT_DIR/scripts/grokbuild-install-update.sh" ]; then
        cp "$ROOT_DIR/scripts/grokbuild-install-update.sh" "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
        chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
        echo "==> Copied install-update helper"
    fi
    if [ -d "$ROOT_DIR/GrokBuild/Resources/Skills" ]; then
        mkdir -p "$APP_BUNDLE/Contents/Resources/Skills"
        cp -R "$ROOT_DIR/GrokBuild/Resources/Skills/." "$APP_BUNDLE/Contents/Resources/Skills/"
        echo "==> Copied bundled skills"
    fi

    chmod +x "$SCRIPT_DIR/bundle-agent-desktop.sh" "$SCRIPT_DIR/codesign-app-bundle.sh"
    "$SCRIPT_DIR/bundle-agent-desktop.sh" "$APP_BUNDLE/Contents/MacOS" || true

    # Copy menu bar icon
    # Looks in these locations (in order):
    #   1. Project root (MenuBarIcon.png / @2x.png) — legacy / docs
    #   2. Asset catalog imageset (recommended location, already in place)
    ICONSET_DIR="$ROOT_DIR/GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset"

    copy_icon() {
        local src="$1"
        local dst="$2"
        if [ -f "$src" ]; then
            cp "$src" "$APP_BUNDLE/Contents/Resources/$dst"
            echo "==> Copied menu bar icon: $(basename "$src") -> $dst"
        fi
    }

    # Base icon
    if [ -f "$ROOT_DIR/MenuBarIcon.png" ]; then
        copy_icon "$ROOT_DIR/MenuBarIcon.png" "MenuBarIcon.png"
    elif [ -f "$ICONSET_DIR/MenuBarIcon.png" ]; then
        copy_icon "$ICONSET_DIR/MenuBarIcon.png" "MenuBarIcon.png"
    fi

    # @2x (retina) — preferred for quality
    if [ -f "$ROOT_DIR/MenuBarIcon@2x.png" ]; then
        copy_icon "$ROOT_DIR/MenuBarIcon@2x.png" "MenuBarIcon@2x.png"
    elif [ -f "$ICONSET_DIR/MenuBarIcon@2x.png" ]; then
        copy_icon "$ICONSET_DIR/MenuBarIcon@2x.png" "MenuBarIcon@2x.png"
    fi

    # @3x (if present)
    if [ -f "$ICONSET_DIR/MenuBarIcon@3x.png" ]; then
        copy_icon "$ICONSET_DIR/MenuBarIcon@3x.png" "MenuBarIcon@3x.png"
    fi
    if [ -f "$ROOT_DIR/MenuBarIcon@3x.png" ]; then
        copy_icon "$ROOT_DIR/MenuBarIcon@3x.png" "MenuBarIcon@3x.png"
    fi

    # App icon (Dock / Applications folder)
    generate_app_icon() {
        local src="$1"
        if [ ! -f "$src" ]; then return; fi
        echo "==> Generating AppIcon.icns from $src"
        local iconset_dir="$BUILD_DIR/AppIcon.iconset"
        rm -rf "$iconset_dir"
        mkdir -p "$iconset_dir"
        sips -z 16 16     "$src" --out "$iconset_dir/icon_16x16.png"     >/dev/null 2>&1 || true
        sips -z 32 32     "$src" --out "$iconset_dir/icon_16x16@2x.png"  >/dev/null 2>&1 || true
        sips -z 32 32     "$src" --out "$iconset_dir/icon_32x32.png"     >/dev/null 2>&1 || true
        sips -z 64 64     "$src" --out "$iconset_dir/icon_32x32@2x.png"  >/dev/null 2>&1 || true
        sips -z 128 128   "$src" --out "$iconset_dir/icon_128x128.png"   >/dev/null 2>&1 || true
        sips -z 256 256   "$src" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null 2>&1 || true
        sips -z 256 256   "$src" --out "$iconset_dir/icon_256x256.png"   >/dev/null 2>&1 || true
        sips -z 512 512   "$src" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null 2>&1 || true
        sips -z 512 512   "$src" --out "$iconset_dir/icon_512x512.png"   >/dev/null 2>&1 || true
        sips -z 1024 1024 "$src" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null 2>&1 || true
        iconutil -c icns "$iconset_dir" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
        rm -rf "$iconset_dir"
    }

    if [ -f "$ROOT_DIR/AppIcon.png" ]; then
        generate_app_icon "$ROOT_DIR/AppIcon.png"
    elif [ -f "$ROOT_DIR/AppIcon1024.png" ]; then
        generate_app_icon "$ROOT_DIR/AppIcon1024.png"
    else
        # Fallback using the menu bar icon source (will be low-res; provide AppIcon.png for best results)
        if [ -f "$ICONSET_DIR/MenuBarIcon@3x.png" ]; then
            echo "==> Using MenuBarIcon as fallback AppIcon (add a 1024x1024 AppIcon.png in project root for proper quality)"
            generate_app_icon "$ICONSET_DIR/MenuBarIcon@3x.png"
        fi
    fi

    # Info.plist for a normal app (with Dock presence + menu bar icon)
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>GrokBuild uses the microphone for voice input in the chat composer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>GrokBuild transcribes your speech to text for chat messages.</string>
</dict>
</plist>
EOF

    chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

    if [ -n "$SIGN_IDENTITY" ]; then
        "$SCRIPT_DIR/codesign-app-bundle.sh" "$APP_BUNDLE" "$SIGN_IDENTITY"
    else
        "$SCRIPT_DIR/codesign-app-bundle.sh" "$APP_BUNDLE"
    fi

else
    echo "ERROR: No Package.swift found."
    echo "Run: swift build -c release"
    exit 1
fi

echo "==> App bundle ready: $APP_BUNDLE"

# Create DMG
echo "==> Creating DMG..."
DMG_PATH="$DIST_DIR/${APP_NAME}-macOS.dmg"
rm -f "$DMG_PATH"

DMG_STAGING="$DIST_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo ""
echo "==> Done!"
echo "   App:  $APP_BUNDLE"
echo "   DMG:  $DMG_PATH"
echo ""
echo "To open the app:"
echo "   open $APP_BUNDLE"
if [ -z "$SIGN_IDENTITY" ]; then
    echo ""
    echo "For signed builds, set SIGN_IDENTITY in .env or run:"
    echo "   make signed SIGN_IDENTITY=\"Developer ID Application: ...\""
fi
