#!/bin/sh
# Pull a bad release and send everyone back to a good one.
#   sh scripts/yank.sh 1.3.0 [--to 1.2.4] [--reason "crashes on launch"]
# Default --to is the newest release before it. What happens:
#   1. v1.3.0 gets "[YANKED]" in its title and a warning at the top of its notes; it stops being "latest"
#   2. v1.2.4 becomes "latest" again, and its latest.json lists 1.3.0 under "yanked"
#   3. copies on 1.3.0 see "this version was pulled", and `upgrade` takes them back to 1.2.4 (a verified downgrade)
#   4. the Homebrew tap goes back to 1.2.4; the beta channel too; your webhook gets X-Shipcrate-Event: yank
# The files of 1.3.0 stay downloadable (nothing is deleted). To fix forward, just release 1.3.1.
#   --file F   only add the version to a local latest.json's "yanked" list (testing)
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
BAD=""; GOOD=""; REASON=""; FILE=""; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --to) GOOD="${2:?}"; shift ;; --reason) REASON="${2:?}"; shift ;; --file) FILE="${2:?}"; shift ;; --yes|-y) YES=1 ;;
  -*) echo "unknown flag $1"; exit 2 ;; *) BAD="${1#v}" ;;
esac; shift; done
[ -n "$BAD" ] || { sed -n '2,12p' "$0"; exit 2; }
die() { echo "✗ $*"; exit 1; }

add_yanked() { # file version
  cur=$(sed -n 's/^  "yanked": \[\(.*\)\].*/\1/p' "$1")
  printf '%s' "$cur" | grep -q "\"$2\"" && return 0
  manifest_set "$1" yanked "[${cur:+$cur, }\"$2\"]"
}
if [ -n "$FILE" ]; then add_yanked "$FILE" "$BAD"; echo "✓ $FILE: $BAD yanked"; exit 0; fi

gh release view "v$BAD" --repo "$REPO" >/dev/null 2>&1 || die "no release v$BAD"
if [ -z "$GOOD" ]; then
  GOOD=$(gh release list --repo "$REPO" --exclude-pre-releases --limit 50 --json tagName,name -q '.[] | select(.name | startswith("[YANKED]") | not) | .tagName' \
    | grep -E '^v[0-9]' | sed 's/^v//' | while read -r t; do [ "$t" != "$BAD" ] && [ "$(printf '%s\n%s\n' "$t" "$BAD" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$t" ] && echo "$t"; done | head -1)
fi
[ -n "$GOOD" ] || die "no earlier good release to go back to (use --to)"
GOOD="${GOOD#v}"
echo "Yank $PRODUCT $BAD and send everyone back to $GOOD${REASON:+ (reason: $REASON)}."
if [ $YES = 0 ]; then printf 'Continue? [y/N] '; read -r ok; case "$ok" in y|Y|yes) ;; *) die "cancelled";; esac; fi

W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
M=$(fetch_manifest "v$GOOD" "$W") || die "v$GOOD has no latest.json"
add_yanked "$M" "$BAD"
manifest_set "$M" rollout ""
manifest_set "$M" announcement "$(printf '{ "id": "yank-%s", "level": "warning", "message": %s, "url": "", "below": "" }' "$BAD" \
  "$(printf '%s' "$PRODUCT $BAD was pulled${REASON:+: $REASON}. Run upgrade to go back to $GOOD." | json_string)")"
gh release upload "v$GOOD" "$M" --repo "$REPO" --clobber
gh release edit "v$GOOD" --repo "$REPO" --latest >/dev/null
OLD=$(gh release view "v$BAD" --repo "$REPO" --json body -q .body)
printf '> ⚠️ **Yanked**: this release was pulled%s. Use %s instead.\n\n%s\n' "${REASON:+ ($REASON)}" "v$GOOD" "$OLD" > "$W/notes.md"
gh release edit "v$BAD" --repo "$REPO" --title "[YANKED] $PRODUCT $BAD" --notes-file "$W/notes.md" --latest=false >/dev/null
sh scripts/channel.sh "$M" >/dev/null 2>&1 || true
sh scripts/tap.sh "$GOOD" || true
mkdir -p dist && cp "$M" dist/latest.json && SHIPCRATE_EVENT=yank sh scripts/notify.sh || true
echo "✓ $BAD yanked; latest is $GOOD again. Copies on $BAD are told to run upgrade."
