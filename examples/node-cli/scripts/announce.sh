#!/bin/sh
# Send a message to every installed copy, without a new version. Apps and CLIs show it once at their next
# daily check: a heads-up, a "please upgrade", a survey link, an outage note.
#   sh scripts/announce.sh "Message" [--level info|warning|security] [--url https://…] [--below 1.4.0]
#   sh scripts/announce.sh --clear
#   --below V   only versions older than V see it (e.g. "please upgrade" for old releases)
#   --file F    edit a local latest.json instead of the published one (testing)
# It rewrites latest.json on the newest GitHub release (asks first) and calls your webhook (scripts/notify.sh).
# The message is display-only text: clients never run or download anything because of it.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
MSG=""; LEVEL=info; URL=""; BELOW=""; FILE=""; CLEAR=0; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --level) LEVEL="${2:?}"; shift ;; --url) URL="${2:?}"; shift ;; --below) BELOW="${2:?}"; shift ;;
  --file) FILE="${2:?}"; shift ;; --clear) CLEAR=1 ;; --yes|-y) YES=1 ;;
  -*) echo "unknown flag $1"; exit 2 ;; *) MSG="$1" ;;
esac; shift; done
die() { echo "✗ $*"; exit 1; }
[ $CLEAR = 1 ] || [ -n "$MSG" ] || { sed -n '2,9p' "$0"; exit 2; }
case "$LEVEL" in info|warning|security) ;; *) die "--level must be info, warning or security" ;; esac
[ -z "$URL" ] || case "$URL" in https://*) ;; *) die "--url must be https" ;; esac
[ ${#MSG} -le 280 ] || die "keep it under 280 characters"

TMP=$(mktemp -d); trap 'rm -rf "${TMP:?}"' EXIT
if [ -n "$FILE" ]; then cp "$FILE" "$TMP/latest.json"
else
  TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName) || die "no published release found"
  gh release download "$TAG" --repo "$REPO" --pattern latest.json --dir "$TMP" || die "release $TAG has no latest.json"
fi

ID=$(date -u +%Y%m%dT%H%M%SZ)
cp "$TMP/latest.json" "$TMP/new.json"
if [ $CLEAR = 1 ]; then manifest_set "$TMP/new.json" announcement ""
else manifest_set "$TMP/new.json" announcement "$(printf '{ "id": "%s", "level": "%s", "message": %s, "url": "%s", "below": "%s" }' \
  "$ID" "$LEVEL" "$(printf '%s' "$MSG" | json_string)" "$URL" "$BELOW")"; fi

if [ -n "$FILE" ]; then cp "$TMP/new.json" "$FILE"; echo "✓ updated $FILE"; exit 0; fi
echo "Announcement for everyone on $PRODUCT${BELOW:+ below $BELOW} (level: $LEVEL):"
echo "  ${MSG:-(clearing the current announcement)}"
if [ $YES = 0 ]; then printf 'Publish it to latest.json on %s %s? [y/N] ' "$REPO" "$TAG"; read -r ok; case "$ok" in y|Y|yes) ;; *) die "cancelled";; esac; fi
cp "$TMP/new.json" "$TMP/latest.json"
sh scripts/sign.sh "$TMP/latest.json" >/dev/null
gh release upload "$TAG" "$TMP"/latest.json* --repo "$REPO" --clobber
echo "✓ published: clients show it once, at their next daily check"
mkdir -p dist && cp "$TMP/latest.json" dist/latest.json && SHIPCRATE_EVENT=announcement sh scripts/notify.sh || true
