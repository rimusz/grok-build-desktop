#!/usr/bin/env bash
# Copy agent-desktop into an app bundle's Contents/MacOS directory.
# Usage: bundle-agent-desktop.sh /path/to/GrokBuild.app/Contents/MacOS

set -euo pipefail

DEST_DIR="${1:?destination MacOS directory required}"
SRC=""

if [ -n "${AGENT_DESKTOP_PATH:-}" ] && [ -x "${AGENT_DESKTOP_PATH}" ]; then
    SRC="${AGENT_DESKTOP_PATH}"
else
    for candidate in \
        /opt/homebrew/bin/agent-desktop \
        /usr/local/bin/agent-desktop \
        "${HOME}/.local/bin/agent-desktop" \
        "${HOME}/bin/agent-desktop"; do
        if [ -x "$candidate" ]; then
            SRC="$candidate"
            break
        fi
    done
fi

if [ -z "$SRC" ] && [ -n "${PATH:-}" ]; then
    IFS=':' read -ra path_dirs <<< "$PATH"
    for dir in "${path_dirs[@]}"; do
        if [ -x "$dir/agent-desktop" ]; then
            SRC="$dir/agent-desktop"
            break
        fi
    done
fi

if [ -z "$SRC" ]; then
    echo "WARNING: agent-desktop not found. Install with: npm install -g agent-desktop" >&2
    return 1 2>/dev/null || exit 1
fi

cp "$SRC" "$DEST_DIR/agent-desktop"
chmod +x "$DEST_DIR/agent-desktop"
echo "==> Bundled agent-desktop from $SRC"
