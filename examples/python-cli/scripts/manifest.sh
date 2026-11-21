#!/bin/sh
# Write dist/latest.json: the update manifest that the installers, the in-app/CLI updaters and your own servers read.
# Published with every release, so its stable URL is https://github.com/OWNER/REPO/releases/latest/download/latest.json
#   [ROLLOUT=N] [ROLLOUT_DAYS=D] sh scripts/manifest.sh <version> [--security]      (reads dist/*.sha256 and dist/notes.md)
# Optional keys added later by other scripts: "rollout" (rollout.sh), "announcement" (announce.sh), "yanked" (yank.sh).
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
V="${1:?usage: manifest.sh <version> [--security]}"; SEC=false; [ "${2:-}" = --security ] && SEC=true
grep -qi '\[security\]' dist/notes.md 2>/dev/null && SEC=true
BASE="https://github.com/$REPO/releases/download/v$V"
{
  printf '{\n  "schema": 1,\n  "name": %s,\n  "version": "%s",\n  "tag": "v%s",\n' "$(printf '%s' "$PRODUCT" | json_string)" "$V" "$V"
  printf '  "published": "%s",\n  "security": %s,\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SEC"
  # staged rollout: only N% of copies are offered the update (ROLLOUT=N); 100 = everyone
  case "${ROLLOUT:-100}" in 100|"") ;; *) printf '  "rollout": %s,\n' "$ROLLOUT" ;; esac
  # timed rollout: grows to 100% over N days on each client (ROLLOUT_DAYS=N), starting at ROLLOUT (default 0)
  case "${ROLLOUT_DAYS:-}" in ""|0) ;; *[!0-9]*) echo "ROLLOUT_DAYS must be a number" >&2; exit 2 ;; *) printf '  "rollout_days": %s,\n' "$ROLLOUT_DAYS" ;; esac
  printf '  "page": "https://github.com/%s/releases/tag/v%s",\n' "$REPO" "$V"
  printf '  "notes": %s,\n  "assets": {' "$( (cat dist/notes.md 2>/dev/null || true) | json_string)"
  sep=""
  for t in $TARGETS; do
    a=$(asset_for "$t"); [ -f "dist/$a.sha256" ] || continue
    printf '%s\n    "%s": { "name": "%s", "url": "%s/%s", "sha256": "%s" }' "$sep" "$t" "$a" "$BASE" "$a" "$(cut -d' ' -f1 "dist/$a.sha256")"
    sep=","
  done
  printf '\n  }\n}\n'
} > dist/latest.json
[ -n "$sep" ] || { echo "✗ no dist/<asset>.sha256 files for TARGETS='$TARGETS'"; exit 1; }
(cd dist && cat ./*.sha256 > SHA256SUMS)
sh scripts/sign.sh dist/latest.json >/dev/null   # signed updates (if PUBLIC_KEY is set): dist/latest.json.sig
echo "✓ dist/latest.json, dist/SHA256SUMS"
