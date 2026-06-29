---
name: grokbuild-release
description: Versions, packages, signs, notarizes, and publishes GrokBuild GitHub releases. Use when bumping VERSION, running make release, editing release.yml, or helping with codesigning/notarization.
---

# GrokBuild release

## Version files

- `VERSION` — semver shown in About and used for release tags (e.g. `0.1.3`)
- Tag format: `v{VERSION}` (e.g. `v0.1.3`)

## Local release

```bash
cp .env.example .env   # optional: SIGN_IDENTITY, NOTARY_PROFILE
make release           # unsigned, publishes via gh
make release RELEASE_TYPE=notarized
```

Script: `scripts/release.sh`. Requires `gh auth login`.

## CI release

- **Manual workflow dispatch** only — Actions → Release → Run workflow (see `BUILDING.md`)
- Choose `notarized` (default) or `unsigned`
- Tag push auto-release is disabled in `release.yml`

## Checklist

1. Bump `VERSION`
2. **`make test`** — must pass; add tests if release/updater logic changed
3. `make app` or `make dmg` to verify packaging
4. **Update docs** — `BUILDING.md`, `README.md` (install/updates), `ARCHITECTURE.md` (in-app updates section), `scripts/README.md` if scripts changed
5. Commit on feature branch; user creates tag/PR
6. Do not force-push `main` or skip git hooks unless asked

## Update checking in app

`UpdateChecker` compares installed `AppVersion.short` to the newest **notarized** GitHub release (title contains `(Notarized)` or notes mention notarization); unsigned releases are ignored. CLI via `grok update --check --json`.

When changing release naming, assets, or updater behavior, update `ARCHITECTURE.md`, `BUILDING.md`, and `UpdateCheckerTests.swift`.
