---
name: shipcrate
description: Set up or run releases for a project with shipcrate — GitHub releases with SHA-256 checksums and build provenance, a Homebrew formula (CLI) or cask (macOS app), a checked installer script, a quality gate with git hooks and CI, and in-app / CLI update notices with an `upgrade` command. Use when the user asks to "set up releases", "publish a version", "add Homebrew", "add an update check / auto-update", "add a quality gate or pre-commit checks", or to release a new version of a project that has a release.conf.
---

# shipcrate

shipcrate (https://github.com/simarpreetsingh-019/shipcrate) copies parameterised release tooling into a repo.
Everything is plain POSIX shell plus `git` and the GitHub CLI `gh`.

## Rules (always)

- **Ask the user first** before: creating a GitHub repo or Homebrew tap, pushing, tagging, publishing a release,
  or editing anything outside the current repo. A request to "set it up" is not approval to publish.
- **Never put tokens or passwords in files**, commands, workflow YAML or release notes. Local auth is `gh auth login`;
  Actions use `${{ github.token }}`. If a secret is needed, tell the user to add it as a repository secret.
- **Run the gate before releasing:** `sh scripts/check.sh --release` must pass. Don't skip hooks (`--no-verify`) to get past it.
- Don't overwrite existing files without asking; `shipcrate init` already skips them unless told otherwise.
- Update checks stay anonymous: one GET to GitHub's latest-release API, at most daily, no telemetry, opt-out env var.

## Set up a repo

1. Get shipcrate: `git clone https://github.com/simarpreetsingh-019/shipcrate ~/.shipcrate` (or use an existing clone).
2. Collect: product name, type (`app` = macOS .app + cask, `cli` = binary + formula), language (rust/swift/python/node),
   GitHub `owner/repo`, tap repo (`owner/homebrew-name` or `none`), one-line description, bundle ID (apps).
3. Preview, then write:
   ```sh
   ~/.shipcrate/bin/shipcrate init . --dry-run --yes --name NAME --type cli --lang rust --repo OWNER/REPO
   ~/.shipcrate/bin/shipcrate init . --yes --name NAME --type cli --lang rust --repo OWNER/REPO --desc "..."
   ```
4. Open `release.conf` and make `BUILD_CMD`, `ARTIFACT` and `VERSION_CMD` match the project (read its build files).
5. `sh scripts/install-hooks.sh` and `sh scripts/check.sh`; fix what fails.
6. Wire the update check from `updater/` into the code (instructions at the top of each file):
   - Swift app: `Updater.swift` + `UpdateButton` in the UI, `announceLaunch()` at start.
   - Rust/Python/Node CLI: call `notify(version)` after interactive commands; add an `upgrade [--rollback]` command.
7. Commit locally. Then tell the user what's left that needs their OK (tap repo, first release).

## Release a version

1. Add a `## [X.Y.Z]` section to `CHANGELOG.md`.
2. `sh scripts/release.sh X.Y.Z --dry-run`, show the user the notes.
3. Only after the user says yes: `sh scripts/release.sh X.Y.Z --yes` (`--security` for a security fix).
4. Report the release URL and the `gh attestation verify` command.

## Files it adds

`release.conf` · `scripts/{check,release,build-release,release-notes,install-hooks}.sh` · `.githooks/` ·
`.github/workflows/{ci,release}.yml` · `install.sh` · `packaging/homebrew/<name>.rb` · `updater/` · `CHANGELOG.md` · `RELEASING.md`
