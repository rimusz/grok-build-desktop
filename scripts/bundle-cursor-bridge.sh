#!/usr/bin/env bash
# Install Cursor bridge npm deps (if needed) and copy into an app bundle's Resources.
# Usage: bundle-cursor-bridge.sh /path/to/GrokBuild.app/Contents/Resources
#
# Requires Node.js ≥ 22.13 and npm on PATH.
# Soft-skips (exit 0) only when Node/npm is missing or too old so packaging can
# still succeed on machines without a suitable Node. npm install / copy failures
# exit non-zero so callers do not ship a Cursor-capable UI without the sidecar.

set -euo pipefail

DEST_RESOURCES="${1:?destination Contents/Resources directory required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/GrokBuild/Resources/CursorBridge"
NPM_REGISTRY="${NPM_CONFIG_REGISTRY:-https://registry.npmjs.org/}"

if [ ! -f "$SRC_DIR/cursor-openai-bridge.mjs" ] || [ ! -f "$SRC_DIR/package.json" ]; then
    echo "WARNING: Cursor bridge sources missing at $SRC_DIR" >&2
    exit 0
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "WARNING: node/npm not found; skipping Cursor bridge bundle. Install Node ≥ 22.13 to enable the managed bridge." >&2
    exit 0
fi

NODE_VERSION="$(node -p "process.versions.node" 2>/dev/null || echo 0.0.0)"
NODE_MAJOR="$(printf '%s' "$NODE_VERSION" | awk -F. '{print $1+0}')"
NODE_MINOR="$(printf '%s' "$NODE_VERSION" | awk -F. '{print $2+0}')"
if [ "${NODE_MAJOR}" -lt 22 ] || { [ "${NODE_MAJOR}" -eq 22 ] && [ "${NODE_MINOR}" -lt 13 ]; }; then
    echo "WARNING: Node ${NODE_VERSION} is too old for @cursor/sdk (need ≥ 22.13); skipping Cursor bridge bundle." >&2
    exit 0
fi

echo "==> Installing Cursor bridge dependencies in $SRC_DIR (registry: $NPM_REGISTRY)"
(
    cd "$SRC_DIR"
    # Pin public npmjs so a stale lockfile / private mirror cannot leave the .app
    # without CursorBridge (Settings would show "bridge script is missing").
    npm install --omit=dev --no-fund --no-audit --registry="$NPM_REGISTRY"
)

if [ ! -d "$SRC_DIR/node_modules/@cursor/sdk" ]; then
    echo "ERROR: Cursor bridge npm install did not produce node_modules/@cursor/sdk" >&2
    exit 1
fi

DEST="$DEST_RESOURCES/CursorBridge"
rm -rf "$DEST"
mkdir -p "$DEST"
# Copy script + package metadata + node_modules (skip gitignore noise).
rsync -a \
    --exclude '.gitignore' \
    --exclude '.DS_Store' \
    --exclude '*.test.mjs' \
    "$SRC_DIR/" "$DEST/"

if [ ! -f "$DEST/cursor-openai-bridge.mjs" ] || [ ! -d "$DEST/node_modules/@cursor/sdk" ]; then
    echo "ERROR: Cursor bridge copy incomplete at $DEST" >&2
    exit 1
fi

chmod +x "$DEST/cursor-openai-bridge.mjs" "$DEST/cursor-validate-key.mjs" 2>/dev/null || true
echo "==> Bundled Cursor bridge → $DEST"
