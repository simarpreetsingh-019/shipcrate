#!/bin/sh
# Install the `shipcrate` command (macOS, Linux; Windows: use Git Bash or WSL).
#
#   curl -fsSL https://raw.githubusercontent.com/simarpreetsingh-019/shipcrate/main/install.sh -o install.sh
#   less install.sh   # read it first: it's short
#   sh install.sh
#
# It clones the newest release tag of shipcrate into ~/.shipcrate (or updates it) and links
# ~/.local/bin/shipcrate (or /usr/local/bin if writable) to it. Nothing else is touched. Needs git.
# Options (environment): SHIPCRATE_HOME=~/.shipcrate  BIN_DIR=…  VERSION=v0.5.1
set -eu
REPO=https://github.com/simarpreetsingh-019/shipcrate
HOME_DIR="${SHIPCRATE_HOME:-$HOME/.shipcrate}"
say() { printf '%s\n' "$*"; }
command -v git >/dev/null 2>&1 || { say "✗ shipcrate needs git"; exit 1; }
TAG="${VERSION:-$(git ls-remote --tags --refs "$REPO" 'v*' | sed 's#.*/##' | sort -V | tail -1)}"
[ -n "$TAG" ] || TAG=main
if [ -d "$HOME_DIR/.git" ]; then
  say "→ Updating $HOME_DIR to $TAG"
  git -C "$HOME_DIR" fetch -q --tags origin && git -C "$HOME_DIR" -c advice.detachedHead=false checkout -q "$TAG"
else
  say "→ Installing shipcrate $TAG into $HOME_DIR"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" "$REPO" "$HOME_DIR"
fi
BIN="${BIN_DIR:-}"; if [ -z "$BIN" ]; then if [ -w /usr/local/bin ]; then BIN=/usr/local/bin; else BIN="$HOME/.local/bin"; fi; fi
mkdir -p "$BIN" && ln -sf "$HOME_DIR/bin/shipcrate" "$BIN/shipcrate"
say "✓ $("$BIN/shipcrate" version) → $BIN/shipcrate"
case ":$PATH:" in *":$BIN:"*) ;; *) say "  Add it to your PATH: export PATH=\"$BIN:\$PATH\"" ;; esac
say "  Next: cd your-project && shipcrate init --dry-run    ·   Try it: shipcrate demo"
say "  If shipcrate helps, a ⭐ on $REPO helps others find it."
