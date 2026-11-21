# Quick start

> **Want to see it first?** After cloning, run `sh ~/.shipcrate/examples/demo.sh`: a 60-second offline demo of a
> release, the update notice, upgrade, rollback, yank and a refused tampered download. Ready-to-copy projects for
> Rust, Python, Node and a SwiftUI Mac app are in [examples/](https://github.com/simarpreetsingh-019/shipcrate/tree/main/examples).

## 1. Get shipcrate

```sh
git clone https://github.com/simarpreetsingh-019/shipcrate ~/.shipcrate
```

There's nothing to install: it's plain shell. You need `git` and the GitHub CLI (`brew install gh`, then `gh auth login`).

## 2. Add it to your project

```sh
cd your-project
~/.shipcrate/bin/shipcrate init --dry-run    # shows every file it would write
~/.shipcrate/bin/shipcrate init              # asks: name, app or CLI, language, GitHub repo, platforms
```

Or in one line, without the questions:

```sh
~/.shipcrate/bin/shipcrate init . --yes --name mytool --type cli --lang rust \
  --repo you/mytool --targets "macos-arm64 linux-x64 windows-x64"
```

`init` never overwrites a file without asking. Then open `release.conf` and check that `BUILD_CMD`, `ARTIFACT` and
`VERSION_CMD` match your build.

## 3. Turn on the gate

```sh
sh scripts/install-hooks.sh     # quick checks on every commit, full checks on every push
sh scripts/check.sh             # run it once now
```

## 4. Add update checks

Copy the file from `updater/` into your code. The comment at the top of each file shows the two or three lines to add:

| Your product | File | You get |
|---|---|---|
| macOS app (Swift) | `Updater.swift` | Orange **Update** button, "What's new", verified self-update |
| Rust CLI | `update.rs` | Daily notice, `upgrade`, `upgrade --rollback` |
| Python CLI | `update_check.py` | The same |
| Node CLI | `update-check.js` | The same |

Already have a notification system? See [Integrating](../integrating/).

## 5. Release

```sh
# add a "## [0.1.0]" section to CHANGELOG.md, commit, push, wait for CI to pass
sh scripts/release.sh 0.1.0 --dry-run    # builds and shows the notes; publishes nothing
sh scripts/release.sh 0.1.0              # asks, then tags, releases, bumps Homebrew
```

Every release gets a checksum and a provenance attestation for every file, plus `latest.json` for the updaters.
Anyone can check a download:

```sh
gh attestation verify mytool-macos-arm64.tar.gz --repo you/mytool
```

## Using an AI agent?

Install the skill (`sh ~/.shipcrate/skills/install.sh`) and ask your agent to "set up releases with shipcrate".
It runs the same steps and asks you before it pushes or publishes anything.
