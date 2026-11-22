# Changelog

## [Unreleased]

### Added
- **Required updates (minimum version):** `shipcrate min-version X.Y.Z` (or `release.sh … --min-version X.Y.Z`) makes every copy older than X.Y.Z show "UPDATE REQUIRED" at every check, whatever the rollout; Swift apps get a red "Update required" button and a critical alert. Saved as `MIN_VERSION` in `release.conf` so later releases keep it, and written into the live `latest.json` and beta channel at once. In all four updaters (`min_version` in latest.json), the dashboard (Actions → Required update, and on the Stable card) and `shipcrate status`. Learned from Sparkle's critical updates.
- **`shipcrate plan [X.Y.Z]`** (`release.sh --plan`): what a release would do, in about two seconds and without building: guardrails that would stop it, the file per platform and where it's built, the release files, notes, rollout, security, required update, beta channel, Homebrew and webhook. Exits 1 if something would stop the release. Also a **Plan** button in the dashboard. Learned from `dist plan`.

## [0.5.1] - 2026-11-23

### Added
- **`shipcrate ui`:** a local dashboard for a project, at `http://127.0.0.1:4747`. It shows the live stable release (rollout progress, yanks, announcement), the beta channel, downloads per version and file, releases and the folder's state. Buttons run the gate, doctor, changelog, release preview, stats and webhook test, and, after showing the exact command and asking, rollout, announcements and yank. Local only, with a one-time key in the URL and a local-Host check. Publishing a release stays in the terminal.
- **`shipcrate ui` gets four tabs.** *Stats:* totals, stable vs beta, update checks, downloads per version and per platform, downloads per day and running totals from the daily snapshots (7/30/90 days or all), the newest release's rollout curve with a "now" marker, CSV export, and baseline set/clear. *Actions:* a rollout scheduler with a live curve, an announcement preview (terminal and app), and a step-by-step yank checklist. *Settings:* safe-rollout days, snapshots, where builds run, Homebrew tap, platforms and the credit line, saved to `release.conf` only after you review the diff (settings missing from older files are added with their default); `shipcrate sync` from the page; signed updates explained. Page preferences (start tab, auto-refresh) stay in the browser.
- The demo receiver's live page (`VIEW=1`) updates in place instead of reloading.
- **`shipcrate webhook test`** (`scripts/webhook-test.sh`): sends signed sample release, security, announcement and yank events to your receiver, and checks it refuses wrong and missing signatures. `--postman FILE` writes a Postman collection with the same samples and HMAC signing; a ready-made one is in `examples/notify-receiver/`.
- The demo receiver understands `X-Shipcrate-Event: yank`, and with `VIEW=1` shows a live page of accepted and refused messages on localhost.

### Changed
- **No Actions minutes for nothing:** the daily Stats workflow is only written while `STATS_SNAPSHOTS='on'`. `shipcrate sync` adds it when you turn snapshots on, and offers to remove it when they're off.
- **`release.sh --trust-ci`:** when CI passed on this exact commit, the release skips re-running the whole gate locally (it still requires a clean tree and SECURITY.md). Without the flag, the release says when this applies.

### Fixed
- **`changelog.sh` suggested 1.9.1 after 1.10.0 betas:** betas name the next stable version, so it now suggests 1.10.0 (a bigger bump still wins; betas of older versions are ignored). Found by `shipcrate ui` on Thermo.
- **`shipcrate ui` hardening from edge-case tests:** free text (announcement, yank reason) can't start with "-" or hold control characters (a message "--clear" would have been read as a flag), unknown webhook events and non-object arguments are refused, oversized requests get 413, a busy port gives a clear message, and old projects missing a script are told to run `shipcrate sync`.
- **`webhook test`:** a receiver that isn't running says "no answer", and a receiver that accepts wrong or missing signatures gets a warning that anyone could fake a release.
- `shipcrate sync` refused a checkout at a release tag when the `v1` tag pointed at the same commit.

## [0.5.0] - 2026-11-22

### Fixed (important)
- **The gate flagged every project's own `TOKEN` name as a credential** when the name had 8+ characters (e.g. `makereel`): the exclusion never matched `grep -n` output. Found on makereel.
- **`shipcrate sync` could stop before finishing** (exit 1, version not recorded) when the last file it checked was edited. Found on msh.
- **Projects set up before 0.5 kept old scripts silently:** with no record of what shipcrate wrote, sync treats every differing file as yours. It now says so and that older copies miss fixes (Thermo's `release.sh` would still refuse 1.10.0 after the beta).
- **Python gate:** uses the project's `.venv` when there is one, and says "needs pytest" instead of a confusing unittest error; `.env.example` / `.env.sample` / `.env.template` are no longer blocked.
- **Update-path test for CLIs that ask first:** retries `upgrade -y` / `--yes` when there's no terminal (msh).
- **Pre-release ordering in all 4 updaters:** `1.10.0-beta.2` was treated as equal to `1.10.0-beta.1`, so beta testers couldn't get the next beta. In Swift, `1.10.0` was also equal to `1.10.0-beta.1`, so beta testers never got the final release. Updaters now use semantic-versioning order (beta.1 < beta.2 < beta.10 < rc.1 < release). Found by the new update-path test on Thermo.
- `release.sh` refused `1.10.0` after `1.10.0-beta.1` ("isn't newer"). Versions are now compared with `ver_gt` in `lib.sh`.

### Added
- **Safe updates for live apps (6 rules):** `shipcrate sync` (shipcrate releases only, records `SHIPCRATE_VERSION`); `release.sh` asks for a beta first, a passing `scripts/update-path-test.sh` (the last stable copy updates itself to the new build, locally) and a timed rollout (`SAFE_ROLLOUT_DAYS`, default 7) when shipcrate's code or the updater changed; it refuses to drop download names the last release had. Escape hatches: `--skip-beta`, `--skip-update-test`, `--full-rollout`, `--allow-renamed-assets`.
- **Your pieces stay yours:** `sync` and `doctor` list a project's own installer, updater copy and release script, explain what shipcrate's version would add, and point to `shipcrate sync --show FILE` for a diff. `keygen.sh` explains signed updates (today vs after, cost of a lost key) and asks first.
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
