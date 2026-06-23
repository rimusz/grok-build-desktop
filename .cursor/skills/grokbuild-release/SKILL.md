---
name: grokbuild-release
description: Versions, packages, signs, notarizes, and publishes GrokBuild GitHub releases. Use when bumping VERSION, running make release, editing release.yml, or helping with codesigning/notarization.
---

# GrokBuild release

## Version files

- `VERSION` — semver shown in About (e.g. `0.1.3`)
- `BUILD_NUMBER` — build counter in parentheses
- Tag format: `v{VERSION}` (e.g. `v0.1.3`)

## Local release

```bash
cp .env.example .env   # optional: SIGN_IDENTITY, NOTARY_PROFILE
make release           # unsigned, publishes via gh
make release RELEASE_TYPE=notarized
```

Script: `scripts/release.sh`. Requires `gh auth login`.

## CI release

- Tag push `v*` → `.github/workflows/release.yml` (unsigned by default)
- Manual workflow dispatch for notarized builds (see `BUILDING.md`)

## Checklist

1. Bump `VERSION` (and `BUILD_NUMBER` if needed)
2. `make test`
3. `make app` or `make dmg` to verify packaging
4. Commit on feature branch; user creates tag/PR
5. Do not force-push `main` or skip git hooks unless asked

## Update checking in app

`UpdateChecker` compares installed `AppVersion.short` to GitHub latest; CLI via `grok update --check --json`.
