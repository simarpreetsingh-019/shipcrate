# Changelog

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
