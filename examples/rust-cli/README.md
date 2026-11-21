# hello-ship: a Rust CLI with shipcrate

A tiny CLI showing shipcrate in a real Rust program. Everything shipcrate-specific is in [`src/main.rs`](src/main.rs)
(about 10 lines, marked `shipcrate`) plus the files `shipcrate init` added.

```sh
cargo run -- Ada                 # 👋 Hello, Ada!  (+ the update notice, when a newer version exists)
cargo run -- upgrade             # install the newest release: download → SHA-256 check → atomic swap
cargo run -- upgrade --rollback  # go back to the previous version
sh ../demo.sh                    # the full story, offline, in 60 seconds
```

## How it was made

```sh
cargo new hello-ship
shipcrate init . $(cat .shipcrate-init)      # the release tooling
```

Then three things in `src/main.rs`:

```rust
#[path = "../updater/update.rs"] mod update;              // or copy updater/update.rs to src/update.rs
update::notify(VERSION);                                  // after a command: one line when an update is out
update::upgrade(VERSION, rollback)                        // the `upgrade` command
```

## What a release looks like

```sh
sh scripts/release.sh 1.1.0 --dry-run    # guardrails, gate, notes; publishes nothing
sh scripts/release.sh 1.1.0              # CI builds macOS (arm64, x64), Linux (x64, arm64) and Windows (x64)
sh scripts/release.sh 1.2.0 --rollout 10 # 10% of users first
sh scripts/yank.sh 1.2.0                 # pull a bad release; users are moved back
```

Users install it with `brew install you/hello-ship/hello-ship`, `install.sh` (macOS/Linux) or `install.ps1` (Windows).
