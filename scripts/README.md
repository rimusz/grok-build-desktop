# Build Scripts

This directory contains command-line tools to build GrokBuild locally.

## Main script: `build-macos-app.sh`

This script packages the SPM-built app into a `.app` bundle and optionally a DMG.
It also handles codesigning when `--sign` is provided.

It is primarily meant for creating distributable builds.

### Usage examples

```bash
# Create unsigned .app + DMG
./scripts/build-macos-app.sh

# Create signed release
./scripts/build-macos-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

## Makefile

The recommended way to drive builds:

```bash
make help
make app
make dmg
make signed SIGN_IDENTITY="..."
```

See [BUILDING.md](../BUILDING.md) for full instructions.

## Icon

The script looks for the menu bar icon in this order:

1. `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/` (recommended / current location)
2. Project root (`MenuBarIcon.png` / `@2x.png`)

It copies the files into the app bundle's `Contents/Resources/`. The icon files are already present in the asset catalog.