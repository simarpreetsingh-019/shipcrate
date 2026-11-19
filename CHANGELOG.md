# Changelog

## [Unreleased]

### Added
- README: badges, author section; CONTRIBUTING.md.

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
