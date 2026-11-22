# shipcrate

[![CI](https://github.com/simarpreetsingh-019/shipcrate/actions/workflows/ci.yml/badge.svg)](https://github.com/simarpreetsingh-019/shipcrate/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/simarpreetsingh-019/shipcrate)](https://github.com/simarpreetsingh-019/shipcrate/releases) [![Stars](https://img.shields.io/github/stars/simarpreetsingh-019/shipcrate?style=social)](https://github.com/simarpreetsingh-019/shipcrate/stargazers) [![Site](https://img.shields.io/badge/site-github.io-orange)](https://simarpreetsingh-019.github.io/shipcrate/) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**Release and update tooling for your products, in one command.** shipcrate drops a tested release system into
any repo: a quality gate with git hooks and CI, a one-command release script, GitHub releases with SHA-256
checksums and build provenance, a Homebrew formula or cask, an installer that verifies what it downloads, and
update notices for macOS apps and command-line tools on macOS, Linux and Windows, with security guardrails and tests
that ship into your project. Plain POSIX shell plus `git` and `gh`; nothing to install.

It's extracted from the release system of [Thermo](https://github.com/simarpreetsingh-019/Thermo), a macOS notch
system monitor, and made generic. Works by hand, and by AI coding agents through the included skills.

## Install

**With AI (about 2 minutes):** in Claude Code:

```text
/plugin install shipcrate --marketplace simarpreetsingh-019/shipcrate
/shipcrate:setup
```

**New project (under 5 minutes):** click **Use this template** at the top of this repo, clone your new repo, then
`sh start.sh` and pick Rust CLI, Python CLI, Node CLI or SwiftUI Mac app. It becomes one clean, ready-to-release
project named after your repo. With the command installed: `shipcrate new rust-cli myapp`.

**In a GitHub workflow:**

```yaml
- uses: simarpreetsingh-019/shipcrate@v1
  with:
    command: check        # or doctor, stats, status, changelog, release-notes
```

**The command, for an existing project:**

```sh
brew install simarpreetsingh-019/shipcrate/shipcrate
```

or, without Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/simarpreetsingh-019/shipcrate/main/install.sh -o install.sh && sh install.sh
```

## Quick start

```sh
cd your-project
shipcrate init --dry-run          # see what it would write
shipcrate init                    # asks: name, app/cli, language, GitHub repo, tap
shipcrate keygen                  # signed updates (recommended)
shipcrate doctor                  # checks the setup, explains fixes
shipcrate changelog --write       # CHANGELOG section from your commits
shipcrate release auto --dry-run  # build + show the release notes, publish nothing
shipcrate release auto            # asks, then tags, pushes, releases, bumps the tap
```

All commands: `shipcrate help`. Each one calls your project's own `scripts/`, so plain `sh scripts/release.sh`
works too (CI and agents use that).

Non-interactive: `shipcrate init DIR --yes --name N --type app|cli --lang rust|swift|python|node --repo OWNER/REPO [--targets "macos-arm64 linux-x64 windows-x64"] [--tap OWNER/homebrew-N|none] [--desc TEXT] [--bundle-id ID]`.

Already have releases or a notification system? See [docs/INTEGRATING.md](docs/INTEGRATING.md): take only the parts
you need, send update notices through your own channels, or have each release POST to your push server.
Platforms: [docs/PLATFORMS.md](docs/PLATFORMS.md).
Message every user without a release: `sh scripts/announce.sh "…"`. Demo push receiver: [examples/notify-receiver](examples/notify-receiver).
Beta channel, staged rollout (`--rollout 10` → `scripts/rollout.sh 100`) and rollback for everyone (`scripts/yank.sh`): see [Integrating](docs/INTEGRATING.md).

## See it work

```sh
sh examples/demo.sh     # 60-second offline demo: release → update notice → upgrade → rollback → yank → tamper refused
```

Ready-to-copy examples: [Rust CLI](examples/rust-cli) · [Python CLI](examples/python-cli) · [Node CLI](examples/node-cli) ·
[SwiftUI Mac app](examples/macos-app) · [notification server](examples/notify-receiver). See [examples/](examples).

## What you get

| File | Does |
|---|---|
| `release.conf` | All settings: names, repo, tap, build command, artifact, how to set the version. No secrets. |
| `scripts/check.sh` | The one quality gate: build, tests, secret scan, blocks key/model files and files > 5 MB, lint, dependency audit (Rust, Swift, Python, Node steps). `--quick` / default / `--release`. |
| `.githooks/` + `scripts/install-hooks.sh` | pre-commit runs `--quick`, pre-push runs the full gate. |
| `scripts/release.sh` | guardrails → gate → set version → build → SHA-256 → `latest.json` → GitHub release with "What's new" → Homebrew tap → webhook. `--dry-run`, `--security`, asks before publishing. |
| `.github/workflows/ci.yml` | Runs the gate on every push and PR. |
| `.github/workflows/release.yml` | On a `v*` tag: builds every target on its own runner, verifies the checksums, writes `latest.json` + `SHA256SUMS`, attests the files, publishes, and calls your webhook (optional). |
| `install.sh`, `install.ps1` | For people without Homebrew (macOS/Linux, Windows): reads `latest.json`, downloads the build for that machine, checks SHA-256 (and the attestation if `gh` is installed), installs. |
| `packaging/homebrew/*.rb` | Formula with a checksum per platform (CLI), or a cask (app). |
| `tests/shipcrate/` | Tests that run in your gate: a good release installs and a tampered one is refused; updater host, checksum, upgrade and rollback rules. |
| `SECURITY.md` | Your project's security policy: reporting, release protections, privacy of the update check. |
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

- **MCP server:** `claude mcp add shipcrate -- shipcrate mcp` (or `codex mcp add …`). It has tools to set up, gate, preview, check status and verify. There are no publishing tools: your agent runs those scripts where you can see and approve them. Cursor and VS Code one-click buttons: [AI agents](https://simarpreetsingh-019.github.io/shipcrate/agents/).
- **llms.txt:** [llms.txt](llms.txt) is a one-page brief any agent can read.

- **Claude Code / Codex:** `sh skills/install.sh` copies `skills/shipcrate/SKILL.md` to `~/.claude/skills/shipcrate`
  and `~/.codex/skills/shipcrate` (asks first). The repo also ships `.agents/skills/shipcrate/`.
- **Cursor:** copy `.cursor/rules/shipcrate.mdc` into your project. **Others:** [AGENTS.md](AGENTS.md).

The skill tells agents to ask before creating repos, pushing or publishing, never to put tokens in files, and to run
the gate before releasing.

## Security

Full details: [SECURITY.md](SECURITY.md).

- **Guardrails:** releases only from the default branch, with green CI for that commit, a CHANGELOG entry, a newer version and a clean tree. In release mode the gate can't skip tests, audits or security checks.
- **Workflow checks:** least-privilege permissions, no `pull_request_target`, no echoed secrets, third-party actions pinned to a commit SHA.
- **Checksums:** every release ships `<asset>.sha256`; the installer and updaters refuse a download that doesn't match.
- **Provenance:** `actions/attest-build-provenance` signs each release file. Verify: `gh attestation verify <file> --repo OWNER/REPO`.
- **No telemetry:** the update check is one anonymous GET to `api.github.com/repos/OWNER/REPO/releases/latest`, at most once a day, with a generic User-Agent. Nothing about the user or machine is sent. Opt out with the env var.
- **No tokens in files:** releases use `gh auth login` locally and `GITHUB_TOKEN` in Actions. The gate scans for GitHub, OpenAI, Hugging Face, Slack, AWS and Google keys and private keys.
- Downloads come only from `github.com/OWNER/REPO/releases`. Apps that aren't notarized: the installer verifies, then clears quarantine, as Homebrew does.

## Developing shipcrate

`sh scripts/check.sh` runs shell syntax checks, a secret scan, and `tests/test-init.sh`, which generates a project for
every type and language and checks the output (`sh -n`, YAML, `ruby -c`, compiles the Rust updater and runs its
tests, typechecks the Swift updater, parses Python and Node). CI runs it on macOS and Linux.

## Roadmap

Coming next: Windows and Linux desktop apps, winget and Scoop, `.deb`/`.rpm`, Go and more languages. See [ROADMAP.md](ROADMAP.md).

## Contributing

Bug reports, ideas and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).
Security issues go to a [private advisory](https://github.com/simarpreetsingh-019/shipcrate/security/advisories/new), not a public issue.

## About the creator

Hi, I'm **Simarpreet Singh**. I build developer tools for macOS and beyond, such as
[Thermo](https://github.com/simarpreetsingh-019/Thermo), the notch system monitor that shipcrate grew out of.

- 🌐 Portfolio: [simarpreetsingh-019.github.io](https://simarpreetsingh-019.github.io)
- 𝕏 Twitter/X: [@simarpreet_019](https://x.com/simarpreet_019)
- ✉️ Email: simarpreetsingh.019@gmail.com
- 🐙 GitHub: [@simarpreetsingh-019](https://github.com/simarpreetsingh-019)

⭐ **If shipcrate saves you time, please star the repo.** It helps other people find it and keeps me working on it.
Using it in a project? I'd love to hear about it: tell me on X or open a discussion.

## License

MIT © Simarpreet Singh
