#!/bin/sh
# Download numbers from GitHub: no tracking, no telemetry, nothing added to your app. GitHub counts every download
# of a release file; this reads those public counts.
#   sh scripts/stats.sh              per version: downloads per platform, beta vs stable, update checks
#   sh scripts/stats.sh --csv        one line per file (date,tag,file,count) for snapshots
#   sh scripts/stats.sh --history F  per-day growth from a snapshot CSV (made by the daily stats workflow)
# Reading the numbers:
#   · latest.json / beta.json downloads = update checks so far; each copy checks at most once a day, so the
#     growth per day (from snapshots) ≈ copies in use that day
#   · archive downloads = installs + upgrades of that version (per platform)
#   · counts only go up, and re-uploading a file (announce, rollout, yank) starts its count again: keep snapshots
#   · counts aren't unique people; Homebrew taps and your own mirrors aren't counted here
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
MODE="${1:-table}"; TSV="${SHIPCRATE_STATS_TSV:-}"   # SHIPCRATE_STATS_TSV=file: use saved data (tests)
fetch() {
  if [ -n "$TSV" ]; then cat "$TSV"; return; fi
  command -v gh >/dev/null 2>&1 || { echo "✗ needs the GitHub CLI (gh)" >&2; exit 1; }
  gh api "repos/$REPO/releases?per_page=100" --paginate \
    --jq '.[] | . as $r | .assets[] | [$r.tag_name, ($r.prerelease|tostring), ($r.name // ""), .name, (.download_count|tostring), $r.published_at] | @tsv'
}
DATA=$(fetch)
[ -n "$DATA" ] || { echo "No releases with files yet."; exit 0; }
case "$MODE" in
  --csv)
    D=$(date -u +%Y-%m-%d)
    printf '%s\n' "$DATA" | awk -F'\t' -v d="$D" '{ printf "%s,%s,%s,%s\n", d, $1, $4, $5 }' ;;
  --history)
    F="${2:?usage: stats.sh --history stats.csv}"
    # per tag: total archive downloads on each snapshot day, and the change since the day before
    awk -F, '$3 ~ /\.(tar\.gz|tgz|zip)$/ { t[$1 SUBSEP $2] += $4; days[$1] = 1; tags[$2] = 1 }
      $3 == "latest.json" || $3 == "beta.json" { c[$1 SUBSEP $3] += $4 }
      END {
        n = 0; for (d in days) dl[++n] = d
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (dl[j] < dl[i]) { x = dl[i]; dl[i] = dl[j]; dl[j] = x }
        printf "%-12s %-18s %10s %8s\n", "date", "version", "downloads", "+day"
        for (tg in tags) { prev = ""; for (i = 1; i <= n; i++) { k = dl[i] SUBSEP tg; if (!(k in t)) continue
          printf "%-12s %-18s %10d %8s\n", dl[i], tg, t[k], (prev == "" ? "" : "+" (t[k] - prev)); prev = t[k] } }
        printf "\n%-12s %14s %14s\n", "date", "stable checks", "beta checks"
        for (i = 1; i <= n; i++) printf "%-12s %14d %14d\n", dl[i], c[dl[i] SUBSEP "latest.json"], c[dl[i] SUBSEP "beta.json"]
      }' "$F" ;;
  *)
    printf '%s · download numbers from GitHub (no tracking)\n\n' "$PRODUCT"
    printf '%s\n' "$DATA" | awk -F'\t' '
      $1 == "channel" { if ($4 == "beta.json") beta = $5; next }
      { tag = $1; if (!(tag in seen)) { order[++n] = tag; seen[tag] = 1; pre[tag] = $2; yank[tag] = ($3 ~ /^\[YANKED\]/); when[tag] = substr($6, 1, 10) }
        if ($4 ~ /\.(tar\.gz|tgz|zip)$/) { plat = $4; sub(/\.(tar\.gz|tgz|zip)$/, "", plat); total[tag] += $5; per[tag] = per[tag] sprintf("  %s %d", plat, $5) }
        if ($4 == "latest.json") checks[tag] = $5 }
      END {
        printf "%-18s %-11s %-9s %10s %14s\n", "version", "published", "kind", "downloads", "update checks"
        for (i = 1; i <= n; i++) { t = order[i]; kind = yank[t] ? "YANKED" : (pre[t] == "true" ? "beta" : "stable")
          printf "%-18s %-11s %-9s %10d %14s\n", t, when[t], kind, total[t], (t in checks ? checks[t] : "-")
          if (per[t] != "") printf "%s\n", "   " per[t] }
        printf "\nbeta channel checks (beta.json): %s\n", (beta == "" ? "-" : beta)
        printf "Numbers are running totals. Each copy checks at most once a day, so the daily growth in checks ≈ copies in use.\n"
        printf "Per-day history: the daily Stats workflow saves snapshots; then  shipcrate stats --history stats.csv\n"
      }' ;;
esac
