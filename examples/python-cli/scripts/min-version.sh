#!/bin/sh
# Required update: copies older than VERSION must update. They get an "UPDATE REQUIRED" notice at every check
# (not once a day like an announcement), it ignores staged rollout, and the app's Update button turns red.
#   sh scripts/min-version.sh 1.4.0            copies before 1.4.0 must update (asks first)
#   sh scripts/min-version.sh --clear          no minimum
#   sh scripts/min-version.sh --show           the minimum in release.conf and on the live release
#   --file F   edit a local latest.json instead (testing)
# Saved as MIN_VERSION in release.conf, so every later release keeps it (commit the change), and written into
# latest.json on the live release and the beta channel now. Use it for a security fix or a server/API change that
# old copies can't work with; for a single bad release, scripts/yank.sh is the better tool.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
NEW=""; CLEAR=0; SHOW=0; FILE=""; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --clear) CLEAR=1 ;; --show) SHOW=1 ;; --file) FILE="${2:?}"; shift ;; --yes|-y) YES=1 ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) echo "unknown flag $1"; exit 2 ;; *) NEW="${1#v}" ;;
esac; shift; done
die() { echo "✗ $*"; exit 1; }
if [ $SHOW = 1 ]; then
  echo "release.conf: MIN_VERSION='${MIN_VERSION:-}'"
  W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
  TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null) && M=$(fetch_manifest "$TAG" "$W" 2>/dev/null) \
    && echo "live ($TAG): $(sed -n 's/^  "min_version": "\(.*\)".*/\1/p' "$M" | grep . || echo none)" || echo "live: no published latest.json"
  exit 0
fi
[ $CLEAR = 1 ] || [ -n "$NEW" ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
if [ $CLEAR = 0 ]; then
  printf '%s' "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || die "not a version: $NEW (like 1.4.0)"
fi
VAL=""; [ $CLEAR = 1 ] || VAL="\"$NEW\""
if [ -n "$FILE" ]; then manifest_set "$FILE" min_version "$VAL"; echo "✓ $FILE: min_version ${NEW:-cleared}"; exit 0; fi

TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName) || die "no published release found"
LIVE="${TAG#v}"
[ $CLEAR = 1 ] || ! ver_gt "$NEW" "$LIVE" || die "$NEW is newer than the live release $LIVE: release it first, then require it"
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
M=$(fetch_manifest "$TAG" "$W") || die "$TAG has no latest.json"
manifest_set "$M" min_version "$VAL"
if [ $CLEAR = 1 ]; then echo "Remove the minimum version: every copy goes back to normal update notices."
else echo "Every $PRODUCT copy older than $NEW will be told an update to $LIVE is required (ignores the rollout)."; fi
if [ $YES = 0 ]; then printf 'Publish to latest.json on %s %s? [y/N] ' "$REPO" "$TAG"; read -r ok; case "$ok" in y|Y|yes) ;; *) die "cancelled";; esac; fi
sh scripts/sign.sh "$M" >/dev/null
gh release upload "$TAG" "$M"* --repo "$REPO" --clobber
sh scripts/channel.sh "$M" >/dev/null 2>&1 || true
# keep it for every later release
if grep -q '^MIN_VERSION=' release.conf; then sed "s/^MIN_VERSION=.*/MIN_VERSION='$NEW'/" release.conf > release.conf.tmp && mv release.conf.tmp release.conf
else printf "# Required update: copies older than this must update (set by scripts/min-version.sh). Empty = none.\nMIN_VERSION='%s'\n" "$NEW" >> release.conf; fi
echo "✓ published${NEW:+: copies before $NEW must update}. release.conf has MIN_VERSION='$NEW': commit it so later releases keep it."
