# Changelog

## [Unreleased]

### Fixed (important)
- **Pre-release ordering in all 4 updaters:** `1.10.0-beta.2` was treated as equal to `1.10.0-beta.1`, so beta testers couldn't get the next beta. In Swift, `1.10.0` was also equal to `1.10.0-beta.1`, so beta testers never got the final release. Updaters now use semantic-versioning order (beta.1 < beta.2 < beta.10 < rc.1 < release). Found by the new update-path test on Thermo.
- `release.sh` refused `1.10.0` after `1.10.0-beta.1` ("isn't newer"). Versions are now compared with `ver_gt` in `lib.sh`.

### Added
- **Safe updates for live apps (6 rules):** `shipcrate sync` (shipcrate releases only, records `SHIPCRATE_VERSION`); `release.sh` asks for a beta first, a passing `scripts/update-path-test.sh` (the last stable copy updates itself to the new build, locally) and a timed rollout (`SAFE_ROLLOUT_DAYS`, default 7) when shipcrate's code or the updater changed; it refuses to drop download names the last release had. Escape hatches: `--skip-beta`, `--skip-update-test`, `--full-rollout`, `--allow-renamed-assets`.
- `shipcrate sync` never overwrites your edits: init and sync record checksums in `.shipcrate/files.sha256`; edited files are shown as a diff and only replaced if you say so (`--yes` keeps them).
- Swift template: a `--update-now` launch flag pattern (the example app has it).

### Fixed
- Swift projects without SwiftPM: a lower-case `tests/` folder no longer triggers `swift test` (macOS disks ignore case).
- Bash scripts are syntax-checked with `bash -n` (by shebang), so process substitution no longer fails the gate.
- `changelog.sh` and `release.sh` ignore moving tags like `v1` and the `channel` release when finding the last version.
- `release.sh` takes a lock (`.git/shipcrate-release.lock`, pid + host) so two releases can't run at once from one folder.
- SwiftLint is skipped locally when it isn't usable (it needs full Xcode) and runs in CI; the gitleaks hint shows once.
- The 5 MB file check suggests how to shrink videos or attach big files to a release; captured output is printed with `printf`.
- **Safety:** the shipped tests (`tests/shipcrate/`) could run a project's *own* `install.sh` (which `init` keeps), and in one project that overwrote a real installed binary. The tests now run only shipcrate's installer (identified by a marker, checked before running it), and only inside a sandbox (temp HOME, XDG folders and PATH). Regression test added.

## [0.4.0] - 2026-11-22

### Added
- **Claude Code plugin:** `/plugin install shipcrate --marketplace simarpreetsingh-019/shipcrate` brings the MCP server, skill, `/shipcrate:setup` (about 2 minutes) and `/shipcrate:release`.
- **GitHub Action:** `uses: simarpreetsingh-019/shipcrate@v1` runs check, doctor, stats, status, changelog or release-notes in any workflow. Publishing stays in your terminal.
- Swift updater: updates now work when the app was renamed (e.g. "App 2.app"); first found and fixed in Thermo.
- **New projects in under 5 minutes:** `shipcrate new <rust-cli|python-cli|node-cli|macos-app> <dir>`, or **Use this template** on the shipcrate repo followed by `sh start.sh`; either way you get one ready-to-release project renamed after your repo. shipcrate's own workflows skip in repos made from the template. `tests/test-templates.sh` runs every path as a new user.
- `tools/ci-local.sh`: run the Linux CI job locally in Docker before pushing.
- Swift updater: `updateNow()`, a public `install`, and `<NAME>_UPDATE_MANIFEST` (a mirror or a manifest on this machine) for testing.
- `shipcrate stats --baseline` / `--baseline-clear`: a zero point (saved on your machine only) so your own downloads and testing don't count; `--repo owner/name` for any repository.
- **Signed updates:** `shipcrate keygen` makes an Ed25519 key; every `latest.json` is signed (`latest.json.sig`), and the Swift, Rust, Python and Node updaters verify it before trusting anything. No dependencies, no cost (CryptoKit, Node crypto, RFC 8032 verifiers in Rust and Python, tested with the RFC vectors).
- **One `shipcrate` command:** `check`, `changelog`, `release`, `rollout`, `yank`, `announce`, `status`, `doctor`, `keygen`, `demo`, `mcp`, `self-update`; `install.sh` installer and a Homebrew formula.
- **Timed rollout:** `--rollout-days N` grows an update to 100% over N days on each client.
- **Version and changelog from commits:** `shipcrate changelog` (Conventional Commits) and `shipcrate release auto`.
- **Download stats without tracking:** `shipcrate stats` shows GitHub's download counts per version, platform and channel, plus update checks; an optional daily snapshot workflow (`STATS_SNAPSHOTS='on'`) keeps history for `--history`. MCP tool `shipcrate_stats`.
- **SBOM and Sigstore:** every release gets an SPDX SBOM, an SBOM attestation and keyless Sigstore signatures (free).
- **Examples:** Rust, Python and Node CLIs and a SwiftUI Mac app, plus `examples/demo.sh`, a 60-second offline demo (now with signed updates and a forged-manifest refusal) and `tests/test-examples.sh`.
- **Website:** SEO and AEO (sitemap, JSON-LD, FAQ, `llms-full.txt`), the Contributing page, and `tools/preview.sh` for local previews.
- ROADMAP.md, with learnings from GoReleaser, dist, Sparkle, Velopack, Tauri and release-please.
- Updaters accept a manifest on this machine (`http://127.0.0.1`/`localhost`) for demos and local testing.

### Fixed
- `tap.sh` now also updates the single `sha256` line of hand-written casks and formulas (no `# shipcrate:` markers).
- `latest.json` could be invalid on Debian/Ubuntu machines (mawk) when release notes contained a backslash: JSON escaping now uses portable `sed`.

## [0.3.0] - 2026-11-20

### Added
- **Rollback for everyone:** `scripts/yank.sh` pulls a bad release; copies on it are moved back to the last good version (verified downgrade); Homebrew and the beta channel follow.
- **Beta channel:** pre-release versions go to `channel/beta.json`; users opt in with `<NAME>_CHANNEL=beta` or `Updater.channel = "beta"`.
- **Staged rollout:** `release.sh --rollout N` and `scripts/rollout.sh N`, with a local random bucket (no tracking); security releases and explicit `upgrade` bypass it; Homebrew follows at 100%.
- **Announcements:** `scripts/announce.sh` messages every installed copy without a release; shown once by all updaters; control characters stripped, https links only.
- **MCP server** (`mcp/server.js`, no dependencies): docs, init (a dry run by default), gate, release preview, status, verify; no publishing tools.
- **Agent setup:** one-command installs for Claude Code and Codex, buttons for Cursor and VS Code, `llms.txt`, and a once-only "star the repo" thank-you in every agent file.
- **Notification demo:** `examples/notify-receiver` verifies the signed webhook and forwards to Slack, Discord or your push service; webhook header `X-Shipcrate-Event: release|announcement|yank`.
- **Website:** social preview card (Open Graph / X), share button (system share sheet or X, LinkedIn, Reddit, Hacker News, Bluesky, email, copy link), one design for every page, an AI agents page, copy buttons, a new footer and a live star count. README badges, creator section and CONTRIBUTING.md.
- `scripts/tap.sh` and `scripts/channel.sh` as shared building blocks; `manifest_set` in `lib.sh`.

## [0.2.0] - 2026-11-20

### Added
- Multi-platform CLIs: `TARGETS` (macOS, Linux, Windows; x64 and arm64) built natively per CI runner; per-platform Homebrew checksums; `install.ps1` for Windows.
- `latest.json` release manifest and `SHA256SUMS`; installers and all updaters read the manifest; mirrors supported.
- Integration with existing notification systems: `check()` / `onUpdateAvailable` hooks and a signed release webhook (`scripts/notify.sh`).
- Guardrails: strict release-mode gate, workflow lint, release checks (branch, CI green, CHANGELOG, newer version), SECURITY.md template.
- Shipped tests (`tests/shipcrate/`): installer tamper test, updater host/checksum/upgrade/rollback tests for Swift, Rust, Python, Node.
- Docs: INTEGRATING.md, PLATFORMS.md, SECURITY.md.

## [0.1.0] - 2026-11-20

### Added
- `shipcrate init`: copies filled-in release tooling into a repo (app or CLI; Rust, Swift, Python, Node). `--dry-run`, never overwrites without asking.
- Templates: quality gate + git hooks, `release.sh` (gate → version → build → package → SHA-256 → GitHub release → Homebrew tap), CI and release workflows with build provenance, checked installer, Homebrew formula and cask, CHANGELOG and RELEASING.md.
- Update checks: Swift in-app updater with Update button; Rust, Python and Node CLI notice + `upgrade` / `--rollback`.
- Agent skills: `skills/shipcrate/SKILL.md` (Claude Code, Codex), `AGENTS.md`, Cursor rule, `skills/install.sh`.
