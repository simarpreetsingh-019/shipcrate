#!/bin/sh
# Suggest the next version and write the CHANGELOG section from your commit messages (Conventional Commits).
#   sh scripts/changelog.sh              show the suggested version and the section (changes nothing)
#   sh scripts/changelog.sh --write      add the section to CHANGELOG.md (then edit it as you like)
#   sh scripts/changelog.sh --version    print only the suggested version
# Commit prefixes:  feat: → Added (minor)   fix: → Fixed (patch)   perf:/refactor: → Changed (patch)
#   fix(security): or security: → Security (patch)   feat!: / "BREAKING CHANGE:" → major (minor before 1.0)
#   docs: chore: ci: test: style: build: → left out.  Anything else → Changed.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
MODE="${1:-show}"
LAST=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)   # skips v1, channel, betas
BASE="${LAST#v}"; [ -n "$BASE" ] || BASE=0.0.0
RANGE="${LAST:+$LAST..}HEAD"
LOG=$(git log "$RANGE" --no-merges --format='%s%x1f%b%x1e' 2>/dev/null || true)
[ -n "$LOG" ] || { echo "No commits since ${LAST:-the start}." >&2; exit 1; }

OUT=$(printf '%s' "$LOG" | awk -v RS='\036' -v FS='\037' '
  function add(sec, text) { items[sec] = items[sec] "- " text "\n" }
  {
    subj = $1; body = $2; gsub(/^[ \n]+|[ \n]+$/, "", subj); if (subj == "") next
    brk = (body ~ /BREAKING[ -]CHANGE:/)
    if (match(subj, /^[a-zA-Z]+(\([^)]*\))?!?: */)) {
      head = substr(subj, 1, RLENGTH); text = substr(subj, RLENGTH + 1)
      type = head; sub(/[(!:].*/, "", type); type = tolower(type)
      scope = ""; if (match(head, /\([^)]*\)/)) scope = tolower(substr(head, RSTART + 1, RLENGTH - 2))
      if (head ~ /!:/) brk = 1
    } else { type = "other"; text = subj; scope = "" }
    text = toupper(substr(text, 1, 1)) substr(text, 2)
    if (brk) { level = 3; add("Changed", "**Breaking:** " text); next }
    if (type == "security" || scope == "security") { add("Security", text); if (level < 1) level = 1 }
    else if (type == "feat") { add("Added", text); if (level < 2) level = 2 }
    else if (type == "fix") { add("Fixed", text); if (level < 1) level = 1 }
    else if (type == "perf" || type == "refactor") { add("Changed", text); if (level < 1) level = 1 }
    else if (type ~ /^(docs|chore|ci|test|tests|style|build)$/) next
    else { add("Changed", text); if (level < 1) level = 1 }
  }
  END {
    printf "%d\n", level + 0
    n = split("Security Added Changed Fixed", order, " ")
    for (i = 1; i <= n; i++) if (items[order[i]] != "") printf "### %s\n%s\n", order[i], items[order[i]]
  }')
LEVEL=$(printf '%s\n' "$OUT" | head -1)
SECTION=$(printf '%s\n' "$OUT" | tail -n +2)
[ "$LEVEL" -gt 0 ] || { echo "Only docs/chore/ci/test changes since ${LAST:-the start}: nothing to release." >&2; exit 1; }
MAJ=${BASE%%.*}; REST=${BASE#*.}; MIN=${REST%%.*}; PAT=${REST#*.}; PAT=${PAT%%[-+]*}
if [ "$LEVEL" = 3 ] && [ "$MAJ" = 0 ]; then LEVEL=2; fi        # before 1.0, breaking changes bump the minor
case "$LEVEL" in 3) NEXT="$((MAJ+1)).0.0" ;; 2) NEXT="$MAJ.$((MIN+1)).0" ;; *) NEXT="$MAJ.$MIN.$((PAT+1))" ;; esac
# Betas already name the next version (1.10.0-beta.2 after 1.9.0): the stable release is that version, not 1.9.1.
PRE=$(git tag -l 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-' | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/' | sort -u -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)
if [ -n "$PRE" ] && ver_gt "$PRE" "$BASE" && ver_gt "$PRE" "$NEXT"; then NEXT="$PRE"; fi
DATE=$(date -u +%Y-%m-%d)

case "$MODE" in
  --version) echo "$NEXT" ;;
  --write)
    grep -Eq "^## \[?v?$NEXT\]?([ ]|$)" CHANGELOG.md 2>/dev/null && { echo "CHANGELOG.md already has $NEXT"; exit 0; }
    [ -f CHANGELOG.md ] || printf '# Changelog\n\n' > CHANGELOG.md
    printf '## [%s] - %s\n\n%s\n' "$NEXT" "$DATE" "$SECTION" > .changelog.new
    awk 'FNR==NR { new = new $0 "\n"; next }
         !done && /^## \[/ && $0 !~ /Unreleased/ { printf "%s\n", new; done = 1 } { print }
         END { if (!done) printf "\n%s", new }' .changelog.new CHANGELOG.md > .changelog.out && mv .changelog.out CHANGELOG.md
    rm -f .changelog.new
    echo "✓ CHANGELOG.md: added $NEXT (edit it, commit, then: sh scripts/release.sh $NEXT --dry-run)" ;;
  *) printf 'Last release: %s\nSuggested:    %s\n\n## [%s] - %s\n\n%s\n' "${LAST:-none}" "$NEXT" "$NEXT" "$DATE" "$SECTION" ;;
esac
