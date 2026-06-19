#!/usr/bin/env bash
set -euo pipefail

# Notarization helper for GrokDeck (supports local + CI)
# Usage (local):
#   NOTARY_PROFILE=AC_PASSWORD ./scripts/notarize.sh
#
# Usage (CI with API key):
#   APPLE_API_KEY_PATH=... APPLE_API_KEY_ID=... APPLE_API_ISSUER_ID=... \
#   ./scripts/notarize.sh dist/GrokDeck.app

TARGET="${1:-dist/GrokDeck.app}"
ZIP=""

echo "==> Preparing $TARGET for notarization..."

if [[ "$TARGET" == *.app ]]; then
  ZIP="${TARGET%.app}.zip"
  ditto -c -k --keepParent "$TARGET" "$ZIP"
  SUBMIT_PATH="$ZIP"
elif [[ "$TARGET" == *.dmg || "$TARGET" == *.zip ]]; then
  SUBMIT_PATH="$TARGET"
else
  echo "Unsupported target: $TARGET"
  exit 1
fi

echo "==> Submitting for notarization..."

if [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ]; then
  xcrun notarytool submit "$SUBMIT_PATH" \
    --api-key-path "$APPLE_API_KEY_PATH" \
    --api-key-id "$APPLE_API_KEY_ID" \
    --api-issuer "$APPLE_API_ISSUER_ID" \
    --wait
else
  PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
  xcrun notarytool submit "$SUBMIT_PATH" \
    --keychain-profile "$PROFILE" \
    --wait
fi

echo "==> Stapling..."
if [[ "$TARGET" == *.app ]]; then
  xcrun stapler staple "$TARGET"
elif [[ "$TARGET" == *.dmg ]]; then
  xcrun stapler staple "$TARGET" || true
fi

echo "==> Cleaning up..."
[ -n "$ZIP" ] && rm -f "$ZIP"

echo "==> ✅ Notarization complete for $TARGET"
