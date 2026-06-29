#!/usr/bin/env bash
set -euo pipefail

TARGET=""
NEW_APP=""
PID=""
RELAUNCH=1
RELAUNCH_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --new-app)
            NEW_APP="$2"
            shift 2
            ;;
        --pid)
            PID="$2"
            shift 2
            ;;
        --relaunch-only)
            RELAUNCH_ONLY=1
            shift
            ;;
        --no-relaunch)
            RELAUNCH=0
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --target PATH (--new-app PATH | --relaunch-only) --pid PID [--no-relaunch]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$TARGET" || -z "$PID" ]]; then
    echo "Missing required arguments." >&2
    echo "Usage: $0 --target PATH (--new-app PATH | --relaunch-only) --pid PID [--no-relaunch]" >&2
    exit 2
fi

if [[ "$RELAUNCH_ONLY" -eq 0 ]]; then
    if [[ -z "$NEW_APP" ]]; then
        echo "Missing --new-app (or pass --relaunch-only)." >&2
        exit 2
    fi
    if [[ ! -d "$NEW_APP" ]]; then
        echo "New app bundle not found: $NEW_APP" >&2
        exit 1
    fi
fi

if [[ ! -d "$TARGET" ]]; then
    echo "Target app bundle not found: $TARGET" >&2
    exit 1
fi

for _ in $(seq 1 120); do
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    sleep 0.5
done

if kill -0 "$PID" 2>/dev/null; then
    echo "Timed out waiting for process $PID to exit." >&2
    exit 1
fi

if [[ "$RELAUNCH_ONLY" -eq 0 ]]; then
    ditto "$NEW_APP" "$TARGET"
    xattr -cr "$TARGET" 2>/dev/null || true
fi

if [[ "$RELAUNCH_ONLY" -eq 1 || "$RELAUNCH" -eq 1 ]]; then
    open "$TARGET"
fi
