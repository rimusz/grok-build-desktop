---
name: grokbuild-release
description: Publishes a GrokBuild GitHub release from a clean main. Use when the user asks to release, run make release, or publish a GrokBuild version.
---

# GrokBuild release

1. Ensure the working tree is clean.
2. `git switch main`
3. `git pull --ff-only`
4. Check set version is higher than existing release.
5. `make release`
6. Monitor and report the result.

Stop if the tree is dirty, `git pull --ff-only` fails, or `VERSION` is not higher than the latest GitHub release (`gh release list`; tag `v{VERSION}`).

Do not bump `VERSION`, commit, or force-push. Stream `make release` and report pass/fail plus the release URL.
