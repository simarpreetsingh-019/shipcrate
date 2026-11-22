#!/bin/sh
# Point the Homebrew tap at version $1 (used by release.sh, rollout.sh 100 and yank.sh).
#   sh scripts/tap.sh 1.2.0
# Reads that release's SHA256SUMS, rewrites version + per-platform sha256 lines, commits and pushes the tap.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
V="${1:?usage: tap.sh <version>}"; V="${V#v}"
[ "$TAP_REPO" != none ] || { echo "• no Homebrew tap configured"; exit 0; }
case "$V" in *-*) echo "• $V is a pre-release: Homebrew stays on the stable version"; exit 0 ;; esac
gh repo view "$TAP_REPO" >/dev/null 2>&1 || { echo "• Tap $TAP_REPO doesn't exist. Ask the owner, create it (gh repo create $TAP_REPO --public), copy packaging/homebrew/$(basename "$TAP_FILE") to $TAP_FILE, then rerun."; exit 0; }
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
gh release download "v$V" --repo "$REPO" --pattern SHA256SUMS --dir "$W" || { echo "✗ v$V has no SHA256SUMS"; exit 1; }
gh repo clone "$TAP_REPO" "$W/tap" -- -q
F="$W/tap/$TAP_FILE"
if [ ! -f "$F" ]; then mkdir -p "$(dirname "$F")"; cp "packaging/homebrew/$(basename "$TAP_FILE")" "$F"; git -C "$W/tap" add "$TAP_FILE"; fi
sed -E "s/^  version \".*\"/  version \"$V\"/" "$F" > "$F.new" && mv "$F.new" "$F"
for t in $TARGETS; do
  a=$(asset_for "$t"); sha=$(awk -v a="$a" '$2==a || $2=="*"a {print $1}' "$W/SHA256SUMS")
  [ -n "$sha" ] || continue
  sed -E "s/sha256 \"[0-9a-f]*\"( *# shipcrate:$t)$/sha256 \"$sha\"\\1/" "$F" > "$F.new" && mv "$F.new" "$F"
done
# A single-platform tap file written by hand (no "# shipcrate:<target>" markers): update its one sha256 line.
set -- $TARGETS
if [ $# -eq 1 ] && ! grep -q '# shipcrate:' "$F"; then
  sha=$(awk -v a="$(asset_for "$1")" '$2==a || $2=="*"a {print $1}' "$W/SHA256SUMS")
  [ -n "$sha" ] && sed -E "s/^  sha256 \"[0-9a-f]*\"/  sha256 \"$sha\"/" "$F" > "$F.new" && mv "$F.new" "$F"
fi
if git -C "$W/tap" diff --quiet; then echo "• $TAP_REPO already on $V"; else git -C "$W/tap" commit -qam "$TOKEN $V" && git -C "$W/tap" push -q && echo "✓ $TAP_REPO → $V"; fi
