#!/bin/sh
# Install the lint and dependency-audit tools the release gate requires, on a CI runner.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
case "$KIT_LANG" in
  rust)   cargo audit --version >/dev/null 2>&1 || cargo install cargo-audit --locked --quiet ;;
  python) pipx install --quiet pip-audit && pipx install --quiet ruff ;;
  swift)  command -v swiftlint >/dev/null || brew install --quiet swiftlint ;;
  node)   : ;;  # npm audit ships with npm
esac
