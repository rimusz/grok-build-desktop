#!/usr/bin/env bash
set -euo pipefail

# Build and publish a GitHub release (mirrors .github/workflows/release.yml).
#
# Usage:
#   make release
#   make release RELEASE_TYPE=notarized SIGN_IDENTITY="Developer ID Application: ..."
#   make release RELEASE_VERSION=v0.1.4   # must match VERSION file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-GrokBuild}"
RELEASE_TYPE="${RELEASE_TYPE:-unsigned}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

app_version="$(tr -d '[:space:]' < VERSION)"
build_number="$(tr -d '[:space:]' < BUILD_NUMBER)"
default_tag="v${app_version}"
input_version="${RELEASE_VERSION:-}"

if [ -n "$input_version" ]; then
  case "$input_version" in
    v*) tag_name="$input_version" ;;
    *) tag_name="v${input_version}" ;;
  esac
else
  tag_name="$default_tag"
fi

if [ "$tag_name" != "$default_tag" ]; then
  echo "ERROR: Release tag '$tag_name' does not match VERSION '$default_tag'. Update VERSION or set RELEASE_VERSION."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI is required. Install with: brew install gh && gh auth login"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login"
  exit 1
fi

create_dmg() {
  local dmg_path="dist/${APP_NAME}-macOS.dmg"
  local staging="dist/dmg-staging"

  rm -f "$dmg_path"
  rm -rf "$staging"
  mkdir -p "$staging"
  cp -R "dist/${APP_NAME}.app" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path"
  rm -rf "$staging"
}

write_release_notes() {
  local output_file="$1"

  if [ "$RELEASE_TYPE" = "notarized" ]; then
    cat > "$output_file" <<'EOF'
## Downloads

- `GrokBuild.app.zip` — Signed + notarized build (recommended)
- `GrokBuild-macOS.dmg` — Signed + notarized DMG

This version is properly code-signed and notarized. No Gatekeeper warnings.
EOF
  else
    cat > "$output_file" <<'EOF'
## Downloads

- `GrokBuild.app.zip` — Unsigned build
- `GrokBuild-macOS.dmg` — Unsigned DMG

## How to bypass Gatekeeper protection (unsigned builds)

macOS may block unsigned apps.

**Quick ways to open:**

1. Right-click `GrokBuild.app` (or the DMG) → **Open**
2. Terminal: `xattr -cr /path/to/GrokBuild.app`
3. System Settings → Privacy & Security → "Open Anyway"

---

For a signed + notarized version with no warnings, run:
`make release RELEASE_TYPE=notarized SIGN_IDENTITY="..." NOTARY_PROFILE=...`
EOF
  fi
}

if [ "$RELEASE_TYPE" = "notarized" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "ERROR: SIGN_IDENTITY is required for notarized releases."
    exit 1
  fi
  release_name="${tag_name} (${build_number}) (Notarized)"
else
  release_name="${tag_name} (${build_number}) (Unsigned)"
fi

zip_path="dist/${APP_NAME}.app.zip"
dmg_path="dist/${APP_NAME}-macOS.dmg"
release_body_file="$(mktemp)"
trap 'rm -f "$release_body_file"' EXIT

echo "==> Building ${RELEASE_TYPE} release for ${tag_name}..."

if [ "$RELEASE_TYPE" = "notarized" ]; then
  make signed SIGN_IDENTITY="$SIGN_IDENTITY"
  NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/notarize.sh "dist/${APP_NAME}.app"
  echo "==> Creating DMG from notarized app..."
  create_dmg
else
  make dmg
fi

echo "==> Zipping app..."
ditto -c -k --keepParent "dist/${APP_NAME}.app" "$zip_path"

write_release_notes "$release_body_file"

echo "==> Publishing GitHub release ${tag_name}..."

if gh release view "$tag_name" >/dev/null 2>&1; then
  echo "==> Release ${tag_name} already exists; updating title, notes, and assets..."
  gh release edit "$tag_name" --title "$release_name" --notes-file "$release_body_file"
  gh release upload "$tag_name" "$zip_path" "$dmg_path" --clobber
else
  gh release create "$tag_name" \
    --title "$release_name" \
    --notes-file "$release_body_file" \
    --generate-notes \
    "$zip_path" \
    "$dmg_path"
fi

release_url="$(gh release view "$tag_name" --json url -q .url)"
echo "==> Published: ${release_url}"
