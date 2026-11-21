# Quick start

> **Want to see it first?** After installing, run `shipcrate demo`: a 60-second offline demo of a
> release, the update notice, upgrade, rollback, yank, and a refused tampered download and forged manifest. Ready-to-copy projects for
> Rust, Python, Node and a SwiftUI Mac app are in [examples/](https://github.com/simarpreetsingh-019/shipcrate/tree/main/examples).

## 1. Install shipcrate

```sh
curl -fsSL https://raw.githubusercontent.com/simarpreetsingh-019/shipcrate/main/install.sh -o install.sh && sh install.sh
```

This installs the `shipcrate` command, which is plain shell: it clones the newest release to `~/.shipcrate` and links
the command into your PATH. You also need the GitHub CLI: `brew install gh`, then `gh auth login`.

## 2. Add it to your project

```sh
cd your-project
shipcrate init --dry-run    # shows every file it would write
shipcrate init              # asks: name, app or CLI, language, GitHub repo, platforms
shipcrate doctor            # checks the setup and tells you what to fix
```

Or in one line, without the questions:

```sh
shipcrate init . --yes --name mytool --type cli --lang rust \
  --repo you/mytool --targets "macos-arm64 linux-x64 windows-x64"
```

`init` never overwrites a file without asking. Then open `release.conf` and check that `BUILD_CMD`, `ARTIFACT` and
`VERSION_CMD` match your build.

## 3. Turn on the gate

```sh
sh scripts/install-hooks.sh     # quick checks on every commit, full checks on every push
sh scripts/check.sh             # run it once now
```

## 4. Turn on signed updates (recommended)

```sh
shipcrate keygen
```

This makes an Ed25519 key pair. The private key stays on your machine and, if you say yes, goes into a GitHub
secret for CI; the public key goes into `release.conf` and your update code. From then on every release's
`latest.json` is signed, and apps and CLIs refuse anything that isn't. It's free, with no service to run.

## 5. Add update checks

Copy the file from `updater/` into your code. The comment at the top of each file shows the two or three lines to add:

| Your product | File | You get |
|---|---|---|
| macOS app (Swift) | `Updater.swift` | Orange **Update** button, "What's new", verified self-update |
| Rust CLI | `update.rs` | Daily notice, `upgrade`, `upgrade --rollback` |
| Python CLI | `update_check.py` | The same |
| Node CLI | `update-check.js` | The same |

Already have a notification system? See [Integrating](../integrating/).

## 6. Release

```sh
shipcrate changelog --write        # writes the CHANGELOG section from your commits (feat:, fix:, …)
git commit -am "Changelog" && git push   # wait for CI to pass
shipcrate release auto --dry-run   # the suggested version: builds and shows the notes, publishes nothing
shipcrate release auto             # asks, then tags, releases, bumps Homebrew
```

Want it calmer? `shipcrate release 1.4.0 --rollout-days 7` offers the update to more users each day until everyone
has it, with no follow-up commands.

Every release gets a checksum, a provenance attestation, a keyless Sigstore signature and an SBOM for its files,
plus `latest.json` (signed) for the updaters.
Anyone can check a download:

```sh
gh attestation verify mytool-macos-arm64.tar.gz --repo you/mytool
```

## Using an AI agent?

Connect the MCP server (`claude mcp add shipcrate -- shipcrate mcp`) or install the skill (`sh ~/.shipcrate/skills/install.sh`) and ask your agent to "set up releases with shipcrate".
It runs the same steps and asks you before it pushes or publishes anything.
