# shipcrate feedback from Thermo for Mac (first real user)

Setup: Thermo (Swift macOS app, swiftc + build.sh, no Package.swift, no Xcode project), shipcrate v0.4.0.

## Verdict
Worth it. Got: quality gate + hooks, CI, release with checksums/SBOM/Sigstore, manifest updater,
beta channel, rollout/yank. Doing this by hand = days. Pain was all in setup, not in daily use.

## Problems hit (bugs)
1. **Tests/ vs tests/ clash on case-insensitive APFS.** check.sh used `-d Tests` to mean "SwiftPM tests";
   matched shipcrate's own `tests/` dir → ran `swift test` with no Package.swift. Fix: detect `Package.swift`, not `Tests/`.
2. **Bash scripts checked with `sh -n`.** `2> >(...)` (process substitution) in build.sh failed the syntax check.
   Fix: read the shebang; check `#!/bin/bash` files with `bash -n`, only `#!/bin/sh` with `sh -n`.
3. **Duplicate release paths after `init`.** Repo already had release.sh + updater/; init added scripts/release.sh
   and a second updater. Fix: init should detect existing release.sh / updater and offer "wrap" or "replace", never both.
4. **Updater assumed installed app name == downloaded app name.** Renamed app (Thermo → "Thermo for Mac") failed to swap.
   Fix: pick the first `.app` in the extracted download.
5. **SwiftLint needs full Xcode.** Gate failed on machines with only Command Line Tools.
   Fix: when tool missing and not in CI, print "skipped locally, runs in CI" (we did this; make it default).
6. **5 MB file limit hit by a demo video** (17 MB). Fine rule, but message should suggest `ffmpeg -crf 24` or Git LFS / release asset.
7. **`echo "$OUT"` in test template mangles JSON** (backslash escapes in some shells). Use `printf '%s\n'`.
8. **`channel` release shows up in CHANGELOG generation.** Filter internal tags (channel, v1 moving tag) by default.
9. **Two sessions released from the same folder** (beta.1 pushed by another agent). Add a lock file
   (`.shipcrate/release.lock` with pid + host) so parallel releases refuse.

## Suggestions (new features)
- `shipcrate doctor`: one command that lists missing tools (gitleaks, swiftlint, gh auth, Xcode vs CLT) + fix commands.
- `init --adopt`: scan existing release scripts/workflows and wrap them instead of adding new ones.
- Moving major tag (`v1`) built in (we wrote a wrapper for GitHub Action users).
- Language presets: `swiftc` (no SwiftPM), SwiftPM, Xcode, Go, Rust, Node — pick test/lint/build commands.
- gitleaks optional → show install hint once, not every run.
- Notarization step (optional, needs Apple Developer ID) + clear zip "can't verify" guide for unsigned apps.
- `--dry-run` output: show the final release notes + manifest diff side by side.
- Announce templates for Reddit/HN/X/awesome-lists (Thermo needed a hand-made launch kit).
- Stats: download counts per asset/version in `shipcrate stats` with a weekly CSV.
- Test fixture repo in CI: a tiny swiftc app + a bash-heavy repo on case-insensitive FS (macOS runner) to catch 1, 2, 7.

## Tips for next adopter
- Run `./release.sh X.Y.Z --dry-run` first, always.
- Keep CHANGELOG `## [X.Y.Z]` section ready before release.
- Lint in CI if no Xcode locally.
- Big media → release assets, not the repo.
