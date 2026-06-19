# Building GrokBuild

GrokBuild is built with **Swift Package Manager** (SPM). No Xcode project is required.

## To Build & Run (Minimal Setup)

You only need **Xcode Command Line Tools**:

```bash
xcode-select --install
```

This is sufficient for:
- Compiling the app (`swift build`)
- Creating the `.app` bundle and DMG
- Codesigning and notarization

### Quick start

```bash
make build          # or: swift build -c release
make run            # builds + launches the menu bar app
```

You can also run directly:

```bash
swift build -c release
./.build/release/GrokBuild
```

## For Development (Recommended)

If you're going to edit the SwiftUI code, install the **full Xcode** IDE from the App Store.

**Why full Xcode is worth it:**
- SwiftUI Previews (live canvas) — the biggest advantage
- Much better debugging tools (view inspector, environment values, etc.)
- Smoother experience when working with complex SwiftUI views

You can still build from the terminal with `make` or `swift build` even with full Xcode installed.

```bash
xed .          # open Package.swift in Xcode
```

Then select the `GrokBuild` scheme.

## Packaging

```bash
make app     # creates a distributable .app bundle (includes MenuBarIcon)
make dmg     # creates .app + DMG
```

Output goes to `dist/GrokBuild.app` and `dist/GrokBuild-macOS.dmg`.

The build script automatically copies the menu bar icon (from the asset catalog under `GrokBuild/Resources/...` or project root) into `Contents/Resources/`.

## Codesigning / Distribution

To produce a properly signed build:

```bash
make signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Or run the script directly:

```bash
./scripts/build-macos-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

### What the signing step does
- Builds with `swift build -c release`
- Assembles a proper `.app` bundle structure
- Runs `codesign --force --deep --options runtime`

### Notes on entitlements
The current bundle uses a minimal entitlement for unsigned executable memory (needed by some Swift runtime features). For full notarization you may want to review and expand the entitlements.

## Notarization

To allow users to run the app on modern macOS without Gatekeeper blocking it, notarize the signed app.

### One-liner from Makefile

```bash
make notarize NOTARY_PROFILE=AC_PASSWORD
```

Or let `make dmg` handle it automatically:

```bash
make dmg NOTARY_PROFILE=AC_PASSWORD SIGN_IDENTITY="Developer ID Application: ..."
```

When `NOTARY_PROFILE` is set, `make dmg` will automatically:
- Build + sign the app (if `SIGN_IDENTITY` provided)
- Run notarization (staple the app)
- Rebuild the DMG containing the final stapled app

You only need to set `NOTARY_PROFILE` once per shell or in your environment.

### Manual / Script

You can also run directly:

```bash
./scripts/notarize.sh
```

With custom profile:

```bash
NOTARY_PROFILE=myprofile ./scripts/notarize.sh
```

Create the keychain profile once:

```bash
xcrun notarytool store-credentials "APPLE_CONNECT_PASSWORD" \
  --apple-id your@email.com --team-id YOURTEAMID
```

## GitHub Releases

See `.github/workflows/release.yml`:

- **On every `v*` tag push**: automatically publishes an **unsigned** release with `GrokBuild.app.zip` and the DMG.
- **Manual dispatch** ("notarized" checked): builds the signed + notarized version and publishes it.

**Gatekeeper bypass note** (for unsigned releases) is automatically included in the release body.

## Icon

The menu bar icon lives in the asset catalog:

- `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png`
- `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png` (recommended)
- `...@3x.png` (also supported)

The build script automatically finds the icon from the asset catalog (or as a fallback from the project root) and copies the PNGs into `Contents/Resources/`. 

No need to place duplicate files at the project root — the files already in the imageset are used.
