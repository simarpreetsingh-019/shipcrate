# shipcrate: instructions for AI coding agents (Codex, Cursor, Copilot, Gemini, Claude and others)

The full skill is in [skills/shipcrate/SKILL.md](skills/shipcrate/SKILL.md); this is the same content in short.

**What it is.** `bin/shipcrate init` copies release tooling into a repo: a quality gate (`scripts/check.sh`) with
git hooks and CI, `scripts/release.sh` (gate → version → build → package → SHA-256 → GitHub release → Homebrew tap),
a release workflow with build provenance (`actions/attest-build-provenance`), an installer that verifies checksums,
a Homebrew formula or cask, and update-notice code (`updater/`) for Swift apps and Rust/Python/Node CLIs.

**Rules.**
- Ask the user before creating repos or taps, pushing, tagging or publishing a release.
- Never write tokens, passwords or keys into any file, command or workflow. Use `gh auth login` / `${{ github.token }}`.
- Run `sh scripts/check.sh --release` before releasing; don't bypass hooks.
- Don't weaken guardrails or delete `tests/shipcrate/` to get a release through; fix the cause or ask.
- Existing notification system? Use `check()` / `onUpdateAvailable` and the release webhook (docs/INTEGRATING.md).
- Preview with `--dry-run` first; never overwrite files without asking.
- Update checks: one anonymous GET to GitHub per day at most, no telemetry, opt-out env var, skipped in CI and without a TTY.

**Set up:** `bin/shipcrate init <repo> --dry-run --yes --name N --type app|cli --lang rust|swift|python|node --repo OWNER/REPO`,
then without `--dry-run`, then fix `BUILD_CMD` / `ARTIFACT` / `VERSION_CMD` in `release.conf`, run `sh scripts/check.sh`.

**Release:** CHANGELOG section → `sh scripts/release.sh X.Y.Z --dry-run` → user approves → `sh scripts/release.sh X.Y.Z --yes`.

**Working on shipcrate itself:** run `sh scripts/check.sh` (shell syntax, secret scan, init tests for every type and language).
Keep `skills/shipcrate/SKILL.md` and `.agents/skills/shipcrate/SKILL.md` identical.
