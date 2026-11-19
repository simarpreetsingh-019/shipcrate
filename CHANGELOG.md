# Changelog

## [0.1.0] - 2026-11-20

### Added
- `shipcrate init`: copies filled-in release tooling into a repo (app or CLI; Rust, Swift, Python, Node). `--dry-run`, never overwrites without asking.
- Templates: quality gate + git hooks, `release.sh` (gate → version → build → package → SHA-256 → GitHub release → Homebrew tap), CI and release workflows with build provenance, checked installer, Homebrew formula and cask, CHANGELOG and RELEASING.md.
- Update checks: Swift in-app updater with Update button; Rust, Python and Node CLI notice + `upgrade` / `--rollback`.
- Agent skills: `skills/shipcrate/SKILL.md` (Claude Code, Codex), `AGENTS.md`, Cursor rule, `skills/install.sh`.
