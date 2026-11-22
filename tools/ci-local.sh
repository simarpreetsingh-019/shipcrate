#!/bin/sh
# Run the Linux CI job on this machine before pushing (Docker; GitHub's ubuntu-latest has the same tools).
# Catches Linux-only differences (GNU sed/awk/tar, dash) that a Mac-only check misses. Windows still needs CI.
#   sh tools/ci-local.sh
set -eu
cd "$(dirname "$0")/.."
docker info >/dev/null 2>&1 || { echo "✗ Docker isn't running (OrbStack: orb start)"; exit 1; }
docker build -q -t shipcrate-ci tools/ci >/dev/null
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
git ls-files -z | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp -p "$2" "$1/$2"' _ "$W" {}   # tracked files only, like a checkout
docker run --rm -e CI=true -v "$W:/w" -w /w shipcrate-ci sh -c 'git init -q && git add -A && sh scripts/check.sh'
