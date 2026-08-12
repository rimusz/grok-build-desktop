#!/usr/bin/env bash
# Install Cursor bridge npm deps (if needed) and copy into an app bundle's Resources.
# Usage: bundle-cursor-bridge.sh /path/to/GrokBuild.app/Contents/Resources
#
# Requires Node.js ≥ 22.13 and npm on PATH. Soft-fails with a warning when missing
# so Computer Use / agent-desktop packaging still succeeds.

set -euo pipefail

DEST_RESOURCES="${1:?destination Contents/Resources directory required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/GrokBuild/Resources/CursorBridge"

if [ ! -f "$SRC_DIR/cursor-openai-bridge.mjs" ] || [ ! -f "$SRC_DIR/package.json" ]; then
    echo "WARNING: Cursor bridge sources missing at $SRC_DIR" >&2
    exit 0
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "WARNING: node/npm not found; skipping Cursor bridge bundle. Install Node ≥ 22.13 to enable the managed bridge." >&2
    exit 0
fi

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [ "${NODE_MAJOR}" -lt 22 ]; then
    echo "WARNING: Node ${NODE_MAJOR} is too old for @cursor/sdk (need ≥ 22.13); skipping Cursor bridge bundle." >&2
    exit 0
fi

echo "==> Installing Cursor bridge dependencies in $SRC_DIR"
(
    cd "$SRC_DIR"
    npm install --omit=dev --no-fund --no-audit
)

DEST="$DEST_RESOURCES/CursorBridge"
rm -rf "$DEST"
mkdir -p "$DEST"
# Copy script + package metadata + node_modules (skip gitignore noise).
rsync -a \
    --exclude '.gitignore' \
    --exclude '.DS_Store' \
    --exclude '*.test.mjs' \
    "$SRC_DIR/" "$DEST/"

chmod +x "$DEST/cursor-openai-bridge.mjs" "$DEST/cursor-validate-key.mjs" 2>/dev/null || true
echo "==> Bundled Cursor bridge → $DEST"
