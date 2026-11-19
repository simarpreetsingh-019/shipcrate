#!/bin/sh
# Print the release notes for version $1: the CHANGELOG section ("What's new"), the SHA-256,
# how to install / verify, and a security marker that the updaters look for.
#   sh scripts/release-notes.sh 1.2.0 [extra notes] [--security]
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
V="${1:?usage: release-notes.sh <version> [notes] [--security]}"; shift
EXTRA=""; SECURITY=0
for a in "$@"; do case "$a" in --security) SECURITY=1 ;; *) EXTRA="$a" ;; esac; done
SHA=$(cut -d' ' -f1 "dist/$ASSET.sha256" 2>/dev/null || true)
NEW=$(awk -v v="$V" '$0 ~ "^## \\[?v?"v"\\]?([ ]|$)" {on=1; next} on && /^## / {exit} on {print}' CHANGELOG.md 2>/dev/null | sed '/./,$!d')
[ -n "$NEW" ] || NEW="$EXTRA"
[ "$SECURITY" = 1 ] && printf '> ⚠️ **Security update** [security]: please update soon.\n\n'
printf "## What's new\n\n%s\n" "${NEW:-See the commits since the last release.}"
[ -n "$EXTRA" ] && [ "$EXTRA" != "$NEW" ] && printf '\n%s\n' "$EXTRA"
[ -n "$SHA" ] && printf '\n**SHA-256** (`%s`): `%s`\n' "$ASSET" "$SHA"
printf '\n**Verify the download:** `shasum -a 256 -c %s.sha256` and `gh attestation verify %s --repo %s`\n' "$ASSET" "$ASSET" "$REPO"
if [ "$TAP_REPO" != "none" ]; then
  if [ "$TYPE" = app ]; then printf '\n**Install / update:** `brew install --cask %s/%s/%s` · `brew upgrade --cask %s`, or use the **Update** button in the app.\n' "${TAP_REPO%%/*}" "${TAP_REPO#*/homebrew-}" "$TOKEN" "$TOKEN"
  else printf '\n**Install / update:** `brew install %s/%s/%s` · `brew upgrade %s`, or `%s upgrade`.\n' "${TAP_REPO%%/*}" "${TAP_REPO#*/homebrew-}" "$TOKEN" "$TOKEN" "$BINARY"; fi
fi
printf '\nNo Homebrew? The [installer script](https://github.com/%s#install) downloads the release and checks it for you.\n' "$REPO"
[ -n "$CREDIT" ] && printf '\n%s\n' "$CREDIT"
exit 0
