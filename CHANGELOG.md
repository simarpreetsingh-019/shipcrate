# Changelog

## [Unreleased]

### Added
- `tools/ci-local.sh`: run the Linux CI job locally in Docker before pushing.

- Swift updater: `updateNow()`, a public `install`, and `<NAME>_UPDATE_MANIFEST` (a mirror or a manifest on this machine) for testing.

### Fixed
- `tap.sh` now also updates the single `sha256` line of hand-written casks and formulas (no `# shipcrate:` markers).
- `latest.json` could be invalid on Debian/Ubuntu machines (mawk) when release notes contained a backslash: JSON escaping now uses portable `sed`.

### Added (stats)
- `shipcrate stats --baseline` / `--baseline-clear`: a zero point (saved on your machine only) so your own downloads and testing don't count; `--repo owner/name` for any repository.

## [0.4.0] - 2026-11-22

### Added
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
