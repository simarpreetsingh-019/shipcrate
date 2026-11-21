# shipcrate examples

Small, real projects you can copy. Each one was set up with `shipcrate init` (the exact flags are in its
`.shipcrate-init` file) and then wired up with a few lines, all marked `shipcrate` in the code.

## See it in 60 seconds

```sh
sh examples/demo.sh
```

This runs a complete release-and-update story offline on your machine (needs `cargo` and `python3`). It "releases"
the Rust example to a local web server with shipcrate's own scripts, then shows what a user sees: the update notice,
a verified upgrade, a rollback, an announcement, a bad release being yanked, and a tampered download being refused.
Nothing is published, and nothing outside a temporary folder changes.

## The examples

| Example | What it shows | Try it |
|---|---|---|
| [rust-cli](rust-cli) | Rust CLI: update notice, `upgrade`, `upgrade --rollback`, builds for macOS, Linux and Windows | `cargo run -- Ada` |
| [python-cli](python-cli) | Python CLI: the same, shipped as a single-file zipapp (or via pip/pipx) | `cd src && python3 -m hello_py Ada` |
| [node-cli](node-cli) | Node CLI: the same, bundled into one file (or via npm) | `node bin/hello-node.js Ada` |
| [macos-app](macos-app) | SwiftUI Mac app: orange **Update** button, announcement banner, beta toggle, "What's new" | `sh build.sh && open build/HelloShip.app` |
| [notify-receiver](notify-receiver) | Your own notification server: receives signed release webhooks and forwards them to Slack, Discord or a push service | `RELEASE_WEBHOOK_SECRET=dev node server.js` |

## Use one as a starting point

1. Copy the folder into a new repository.
2. Replace `you/...` in `release.conf`, `install.sh`, `install.ps1` and `packaging/homebrew/*`, or simply rerun
   `shipcrate init` with your own `--repo`.
3. Push, wait for CI, then `sh scripts/release.sh 1.0.0 --dry-run`.

The [Quick start](https://simarpreetsingh-019.github.io/shipcrate/quickstart/) walks through every step.
These examples are tested in shipcrate's CI (`tests/test-examples.sh`), and they're regenerated there to check they
still match what `shipcrate init` produces today.
