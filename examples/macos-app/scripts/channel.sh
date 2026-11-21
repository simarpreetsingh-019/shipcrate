#!/bin/sh
# Publish a manifest to the beta channel: https://github.com/OWNER/REPO/releases/download/channel/beta.json
# Beta users (<NAME>_CHANNEL=beta, or the app's beta setting) read this instead of the stable latest.json.
# Every release, stable or beta, updates it, so beta users always get the newest of both.
#   sh scripts/channel.sh dist/latest.json
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
M="${1:?usage: channel.sh <latest.json>}"
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
cp "$M" "$W/beta.json"
if ! gh release view channel --repo "$REPO" >/dev/null 2>&1; then
  gh release create channel --repo "$REPO" --prerelease --title "Update channels" \
    --notes "Pointers for the beta update channel (beta.json). Not a release: download from the real releases." >/dev/null
fi
gh release upload channel "$W/beta.json" --repo "$REPO" --clobber && echo "✓ beta channel updated"
