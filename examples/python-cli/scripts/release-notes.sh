#!/bin/sh
# Print the release notes for version $1: CHANGELOG section ("What's new"), checksums, install/verify lines,
# and the "[security]" marker that the updaters look for.
#   sh scripts/release-notes.sh 1.2.0 [extra notes] [--security]
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
V="${1:?usage: release-notes.sh <version> [notes] [--security]}"; shift
EXTRA=""; SECURITY=0
for a in "$@"; do case "$a" in --security) SECURITY=1 ;; *) EXTRA="$a" ;; esac; done
NEW=$(awk -v v="$V" '$0 ~ "^## \\[?v?"v"\\]?([ ]|$)" {on=1; next} on && /^## / {exit} on {print}' CHANGELOG.md 2>/dev/null | sed '/./,$!d')
[ "$SECURITY" = 1 ] && printf '> ⚠️ **Security update** [security]: please update soon.\n\n'
printf "## What's new\n\n%s\n" "${NEW:-${EXTRA:-See the commits since the last release.}}"
[ -n "$EXTRA" ] && [ -n "$NEW" ] && printf '\n%s\n' "$EXTRA"
SUMS=""
for t in $TARGETS; do a=$(asset_for "$t"); [ -f "dist/$a.sha256" ] && SUMS="$SUMS
| \`$t\` | \`$a\` | \`$(cut -d' ' -f1 "dist/$a.sha256")\` |"; done
[ -n "$SUMS" ] && printf '\n**SHA-256**\n\n| Platform | File | SHA-256 |\n|---|---|---|%s\n' "$SUMS"
printf '\n**Verify a download:** `shasum -a 256 -c SHA256SUMS --ignore-missing` · `gh attestation verify <file> --repo %s` · or with Sigstore: `cosign verify-blob --bundle <file>.sigstore.json --certificate-identity-regexp "^https://github.com/%s/" --certificate-oidc-issuer https://token.actions.githubusercontent.com <file>`. What'"'"'s inside: `%s.sbom.spdx.json`.\n' "$REPO" "$REPO" "$TOKEN"
if [ "$TAP_REPO" != "none" ]; then
  if [ "$TYPE" = app ]; then printf '\n**Install / update:** `brew install --cask %s/%s/%s` · `brew upgrade --cask %s`, or use the **Update** button in the app.\n' "${TAP_REPO%%/*}" "${TAP_REPO#*/homebrew-}" "$TOKEN" "$TOKEN"
  else printf '\n**Install / update:** `brew install %s/%s/%s` · `brew upgrade %s`, or `%s upgrade`.\n' "${TAP_REPO%%/*}" "${TAP_REPO#*/homebrew-}" "$TOKEN" "$TOKEN" "$BINARY"; fi
fi
printf '\nNo Homebrew? The [installer](https://github.com/%s#install) downloads the release and checks it for you' "$REPO"
case " $TARGETS " in *" windows-"*) printf ' (Windows: `install.ps1`)' ;; esac
printf '.\n'
[ -n "$CREDIT" ] && printf '\n%s\n' "$CREDIT"
exit 0
