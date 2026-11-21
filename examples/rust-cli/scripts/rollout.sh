#!/bin/sh
# Staged rollout: offer the newest release to only PERCENT of installed copies, then widen it.
#   sh scripts/rollout.sh 10        # 10% see the update notice
#   sh scripts/rollout.sh 50
#   sh scripts/rollout.sh 100       # everyone; also bumps the Homebrew tap (held back until now)
#   sh scripts/rollout.sh 0 --days 7   # grow from 0% to 100% over 7 days, on each client, by itself
#   --file F   edit a local latest.json instead (testing)
# Each copy picks a random number 0-99 once and keeps it on the user's machine: nothing is sent or tracked.
# Security releases ignore the percentage, and an explicit `upgrade` always works.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
P=""; FILE=""; YES=0; DAYS=""
while [ $# -gt 0 ]; do case "$1" in --file) FILE="${2:?}"; shift ;; --days) DAYS="${2:?}"; shift ;; --yes|-y) YES=1 ;; *) P="$1" ;; esac; shift; done
case "$DAYS" in ""|[1-9]|[1-9][0-9]) ;; *) echo "✗ --days takes 1-99"; exit 2 ;; esac
case "$P" in ''|*[!0-9]*) sed -n '2,9p' "$0"; exit 2 ;; esac
[ "$P" -le 100 ] || { echo "✗ percent must be 0-100"; exit 2; }
VAL="$P"; [ "$P" = 100 ] && VAL=""     # 100% = no rollout key
[ "$P" = 100 ] && DAYS=""                # 100% now ends a timed rollout too
if [ -n "$FILE" ]; then manifest_set "$FILE" rollout "$VAL"; manifest_set "$FILE" rollout_days "$DAYS"; echo "✓ $FILE: rollout ${P}%${DAYS:+ → 100% over $DAYS days}"; exit 0; fi
TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName)
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
M=$(fetch_manifest "$TAG" "$W")
manifest_set "$M" rollout "$VAL"
manifest_set "$M" rollout_days "$DAYS"
if [ $YES = 0 ]; then printf 'Offer %s %s to %s%% of users? [y/N] ' "$PRODUCT" "$TAG" "$P"; read -r ok; case "$ok" in y|Y|yes) ;; *) echo "cancelled"; exit 1;; esac; fi
gh release upload "$TAG" "$M" --repo "$REPO" --clobber
sh scripts/channel.sh "$M" >/dev/null 2>&1 || true
echo "✓ $TAG offered to ${P}% of users"
[ "$P" = 100 ] && sh scripts/tap.sh "$TAG"
exit 0
