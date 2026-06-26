#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_NUMBER_FILE="$ROOT_DIR/BUILD_NUMBER"
BUILD_NUMBER_VERSION_FILE="$ROOT_DIR/BUILD_NUMBER_VERSION"

version="$(tr -d '[:space:]' < "$VERSION_FILE")"
tracked_version=""
if [ -f "$BUILD_NUMBER_VERSION_FILE" ]; then
    tracked_version="$(tr -d '[:space:]' < "$BUILD_NUMBER_VERSION_FILE")"
fi

current="$(tr -d '[:space:]' < "$BUILD_NUMBER_FILE" 2>/dev/null || true)"
if [[ ! "$current" =~ ^[0-9]+$ ]]; then
    current=0
fi

if [ -n "$tracked_version" ] && [ "$version" != "$tracked_version" ]; then
    next=1
    printf '%s\n' "$version" > "$BUILD_NUMBER_VERSION_FILE"
    printf '%s\n' "$next" > "$BUILD_NUMBER_FILE"
    echo "==> VERSION changed ($tracked_version -> $version); BUILD_NUMBER reset to $next"
elif [ -z "$tracked_version" ]; then
    next=$((current + 1))
    printf '%s\n' "$version" > "$BUILD_NUMBER_VERSION_FILE"
    printf '%s\n' "$next" > "$BUILD_NUMBER_FILE"
    echo "==> BUILD_NUMBER: $current -> $next (tracking VERSION $version)"
else
    next=$((current + 1))
    printf '%s\n' "$next" > "$BUILD_NUMBER_FILE"
    echo "==> BUILD_NUMBER: $current -> $next"
fi
