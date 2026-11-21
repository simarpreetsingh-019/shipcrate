#!/bin/sh
# Point the shipcrate Homebrew formula at a release tag: sh tools/bump-formula.sh v0.4.0 [--push]
# --push commits it to the tap (simarpreetsingh-019/homebrew-shipcrate) with gh; without it, only prints the result.
set -eu
cd "$(dirname "$0")/.."
TAG="${1:?usage: bump-formula.sh vX.Y.Z [--push]}"; V="${TAG#v}"
URL="https://github.com/simarpreetsingh-019/shipcrate/archive/refs/tags/$TAG.tar.gz"
SHA=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)
sed -E "s#archive/refs/tags/v[^\"]*\\.tar\\.gz#archive/refs/tags/$TAG.tar.gz#; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" packaging/homebrew/shipcrate.rb > packaging/homebrew/shipcrate.rb.new
mv packaging/homebrew/shipcrate.rb.new packaging/homebrew/shipcrate.rb
echo "✓ formula → $V ($SHA)"
[ "${2:-}" = --push ] || exit 0
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
gh repo clone simarpreetsingh-019/homebrew-shipcrate "$W" -- -q
mkdir -p "$W/Formula" && cp packaging/homebrew/shipcrate.rb "$W/Formula/shipcrate.rb"
git -C "$W" add -A && git -C "$W" commit -qm "shipcrate $V" && git -C "$W" push -q && echo "✓ tap updated"
