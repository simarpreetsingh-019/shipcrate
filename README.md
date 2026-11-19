# shipcrate

**Release and update tooling for your products, in one command.** shipcrate drops a tested release system into
any repo: a quality gate with git hooks and CI, a one-command release script, GitHub releases with SHA-256
checksums and build provenance, a Homebrew formula or cask, an installer that verifies what it downloads, and
update notices for macOS apps and command-line tools. Plain POSIX shell plus `git` and `gh`; nothing to install.

It's extracted from the release system of [Thermo](https://github.com/simarpreetsingh-019/Thermo), a macOS notch
system monitor, and made generic. Works by hand, and by AI coding agents through the included skills.

## Quick start

```sh
git clone https://github.com/simarpreetsingh-019/shipcrate ~/.shipcrate
cd your-project
~/.shipcrate/bin/shipcrate init --dry-run      # see what it would write
~/.shipcrate/bin/shipcrate init                # asks: name, app/cli, language, GitHub repo, tap
sh scripts/install-hooks.sh && sh scripts/check.sh
sh scripts/release.sh 0.1.0 --dry-run          # build + show the release notes, publish nothing
sh scripts/release.sh 0.1.0                    # asks, then tags, pushes, releases, bumps the tap
```

Non-interactive: `shipcrate init DIR --yes --name N --type app|cli --lang rust|swift|python|node --repo OWNER/REPO [--tap OWNER/homebrew-N|none] [--desc TEXT] [--bundle-id ID]`.

## What you get

| File | Does |
|---|---|
| `release.conf` | All settings: names, repo, tap, build command, artifact, how to set the version. No secrets. |
| `scripts/check.sh` | The one quality gate: build, tests, secret scan, blocks key/model files and files > 5 MB, lint, dependency audit (Rust, Swift, Python, Node steps). `--quick` / default / `--release`. |
| `.githooks/` + `scripts/install-hooks.sh` | pre-commit runs `--quick`, pre-push runs the full gate. |
| `scripts/release.sh` | gate → set version → build → zip/tar.gz → SHA-256 → GitHub release with "What's new" (from CHANGELOG) and the checksum → Homebrew tap bump. `--dry-run`, `--security`, asks before publishing. |
| `.github/workflows/ci.yml` | Runs the gate on every push and PR. |
| `.github/workflows/release.yml` | On a `v*` tag: build, publish, `actions/attest-build-provenance`. Or attests the file you uploaded. |
| `install.sh` | For people without Homebrew: downloads the latest release, checks SHA-256 (and attestation if `gh` is there), installs. |
| `packaging/homebrew/*.rb` | Formula (CLI) or cask (app). |
| `updater/` | Update check code for your language (below). |
| `CHANGELOG.md`, `RELEASING.md` | Templates for your project. |

### Update checks

- **macOS Swift app** (`Updater.swift`): checks GitHub Releases at most daily, shows an orange **Update** button,
  downloads the zip, verifies its SHA-256, the bundle ID and code signature, swaps the app and relaunches.
  Shows "What's new" after updating. Releases made with `--security` get a red **Security update** notice.
- **CLI in Rust, Python, Node** (`update.rs`, `update_check.py`, `update-check.js`): a cached once-a-day check, only
  for interactive commands (never in CI, pipes or scripts), off with `<NAME>_NO_UPDATE_CHECK=1`, one line on stderr.
  `upgrade` verifies the checksum, swaps the binary atomically and keeps the previous one for `upgrade --rollback`.
  Homebrew installs are told to run `brew upgrade`; pip/npm installs get their package manager's command.
  The Rust version uses only the standard library.

## Two worked examples

**Thermo-style macOS app** (cask + in-app updater):
```sh
shipcrate init --name Thermo --type app --lang swift --repo you/Thermo --bundle-id com.you.thermo --desc "Notch system monitor"
```
`BUILD_CMD='sh build.sh'`, `ARTIFACT='build/Thermo.app'`, `BUILD_WHERE='local'`: `release.sh` builds on your Mac,
uploads `Thermo.zip` + `Thermo.zip.sha256`, and bumps `Casks/thermo.rb` in `you/homebrew-thermo`; publishing the
release triggers the attestation. Add `Updater.swift`, put `UpdateButton(updater: .shared)` in your panel.

**msh-style Rust CLI** (formula + `upgrade`):
```sh
shipcrate init --name msh --type cli --lang rust --repo you/modelshelf --desc "Local model manager"
```
`BUILD_WHERE='ci'`: `release.sh` runs the gate, bumps `Cargo.toml`, tags and pushes; the release workflow builds
`msh-macos-arm64.tar.gz` on a macOS runner, publishes it with its checksum and attestation; `release.sh` then bumps
`Formula/msh.rb`. In `main.rs`: `mod update;`, call `update::notify(env!("CARGO_PKG_VERSION"))` after interactive
commands, and route `msh upgrade [--rollback]` to `update::upgrade`.

## For AI agents

- **Claude Code / Codex:** `sh skills/install.sh` copies `skills/shipcrate/SKILL.md` to `~/.claude/skills/shipcrate`
  and `~/.codex/skills/shipcrate` (asks first). The repo also ships `.agents/skills/shipcrate/`.
- **Cursor:** copy `.cursor/rules/shipcrate.mdc` into your project. **Others:** [AGENTS.md](AGENTS.md).

The skill tells agents to ask before creating repos, pushing or publishing, never to put tokens in files, and to run
the gate before releasing.

## Security

- **Checksums:** every release ships `<asset>.sha256`; the installer and updaters refuse a download that doesn't match.
- **Provenance:** `actions/attest-build-provenance` signs each release file. Verify: `gh attestation verify <file> --repo OWNER/REPO`.
- **No telemetry:** the update check is one anonymous GET to `api.github.com/repos/OWNER/REPO/releases/latest`, at most once a day, with a generic User-Agent. Nothing about the user or machine is sent. Opt out with the env var.
- **No tokens in files:** releases use `gh auth login` locally and `GITHUB_TOKEN` in Actions. The gate scans for GitHub, OpenAI, Hugging Face, Slack, AWS and Google keys and private keys.
- Downloads come only from `github.com/OWNER/REPO/releases`. Apps that aren't notarized: the installer verifies, then clears quarantine, as Homebrew does.

## Developing shipcrate

`sh scripts/check.sh` runs shell syntax checks, a secret scan, and `tests/test-init.sh`, which generates a project for
every type and language and checks the output (`sh -n`, YAML, `ruby -c`, compiles the Rust updater and runs its
tests, typechecks the Swift updater, parses Python and Node). CI runs it on macOS and Linux.

## License

MIT © Simarpreet Singh · Created by [Simarpreet Singh](https://simarpreetsingh-019.github.io)
