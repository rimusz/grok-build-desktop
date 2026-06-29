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

# shellcheck source=load-dotenv.sh
source "$SCRIPT_DIR/load-dotenv.sh"
load_dotenv "$ROOT_DIR/.env"

APP_NAME="${APP_NAME:-GrokBuild}"
RELEASE_TYPE="${RELEASE_TYPE:-unsigned}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

app_version="$(tr -d '[:space:]' < VERSION)"
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
  make dmg-package
}

write_release_notes() {
  local output_file="$1"
  local zip_name="${APP_NAME}-${tag_name}.app.zip"
  local dmg_name="${APP_NAME}-${tag_name}-macOS.dmg"

  if [ "$RELEASE_TYPE" = "notarized" ]; then
    cat > "$output_file" <<EOF
## Downloads

- \`${zip_name}\` — Signed + notarized build (recommended)
- \`${dmg_name}\` — Signed + notarized DMG

This version is properly code-signed and notarized. No Gatekeeper warnings.
EOF
  else
    cat > "$output_file" <<EOF
## Downloads

- \`${zip_name}\` — Unsigned build
- \`${dmg_name}\` — Unsigned DMG

## How to bypass Gatekeeper protection (unsigned builds)

macOS may block unsigned apps.

**Quick ways to open:**

1. Right-click \`GrokBuild.app\` (or the DMG) → **Open**
2. Terminal: \`xattr -cr ~/Applications/GrokBuild.app\`
3. System Settings → Privacy & Security → "Open Anyway"

---

For a signed + notarized version with no warnings, set in \`.env\`:

    RELEASE_TYPE=notarized
    SIGN_IDENTITY=Developer ID Application: ...
    NOTARY_PROFILE=AC_PASSWORD

Then run \`make release\`.
EOF
  fi
}

ensure_release_tag() {
  local tag="$1"
  local head_sha
  head_sha="$(git rev-parse HEAD)"

  if ! git rev-parse "$tag" >/dev/null 2>&1; then
    echo "==> Creating tag ${tag} at HEAD..."
    git tag "$tag"
  else
    local tag_sha
    tag_sha="$(git rev-parse "$tag")"
    if [ "$tag_sha" != "$head_sha" ]; then
      echo "==> Tag ${tag} was at ${tag_sha:0:7}; moving to HEAD ${head_sha:0:7} for this release..."
      git tag -f "$tag"
    fi
  fi

  local remote_sha=""
  remote_sha="$(git ls-remote --tags origin "refs/tags/${tag}^{}" 2>/dev/null | awk '{print $1}' | head -1)"
  tag_sha="$(git rev-parse "$tag")"

  if [ -z "$remote_sha" ]; then
    echo "==> Pushing ${tag} to origin..."
    git push origin "$tag"
  elif [ "$remote_sha" != "$tag_sha" ]; then
    echo "==> Updating ${tag} on origin (local release commit differs from remote tag)..."
    git push --force origin "$tag"
  fi
}

if [ "$RELEASE_TYPE" = "notarized" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "ERROR: SIGN_IDENTITY is required for notarized releases (set in .env or environment)."
    exit 1
  fi
fi

zip_path="dist/${APP_NAME}-${tag_name}.app.zip"
dmg_path="dist/${APP_NAME}-${tag_name}-macOS.dmg"
dmg_staging="dist/${APP_NAME}-macOS.dmg"
release_body_file="$(mktemp)"
trap 'rm -f "$release_body_file"' EXIT

echo "==> Building ${RELEASE_TYPE} release for ${tag_name}..."
if [ "$RELEASE_TYPE" = "notarized" ]; then
  echo "==> Signing with: ${SIGN_IDENTITY}"
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  make signed SIGN_IDENTITY="$SIGN_IDENTITY"
  NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/notarize.sh "dist/${APP_NAME}.app"
  echo "==> Creating DMG from notarized app..."
  create_dmg
else
  make app
  echo "==> Creating DMG..."
  create_dmg
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  release_name="${tag_name} (Notarized)"
else
  release_name="${tag_name} (Unsigned)"
fi

echo "==> Zipping app..."
ditto -c -k --keepParent "dist/${APP_NAME}.app" "$zip_path"
cp "$dmg_staging" "$dmg_path"
echo "==> Release assets: $(basename "$zip_path"), $(basename "$dmg_path")"

write_release_notes "$release_body_file"

ensure_release_tag "$tag_name"

echo "==> Publishing GitHub release ${tag_name}..."

if gh release view "$tag_name" >/dev/null 2>&1; then
  echo "==> Release ${tag_name} already exists; updating title, notes, and assets..."
  gh release edit "$tag_name" --title "$release_name" --notes-file "$release_body_file"
  gh release upload "$tag_name" "$zip_path" "$dmg_path" --clobber
else
  gh release create "$tag_name" \
    --title "$release_name" \
    --draft \
    --generate-notes \
    "$zip_path" \
    "$dmg_path"

  generated_notes="$(gh release view "$tag_name" --json body -q .body)"
  {
    cat "$release_body_file"
    echo ""
    echo "---"
    echo ""
    printf '%s\n' "$generated_notes"
  } > "${release_body_file}.combined"
  mv "${release_body_file}.combined" "$release_body_file"

  gh release edit "$tag_name" --notes-file "$release_body_file" --draft=false
fi

release_url="$(gh release view "$tag_name" --json url -q .url)"
echo "==> Published: ${release_url}"
