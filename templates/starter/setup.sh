#!/bin/sh
# Make this template yours, in one command:   sh setup.sh
# It renames the example ({{OLD_NAME}}) to your project everywhere: code, release settings, installers, Homebrew
# file and update checks. It reads your GitHub repo from `git remote`, turns on the git hooks, and offers signed
# updates. Then it deletes itself. Options: --name NAME  --repo OWNER/NAME  --yes (no questions)
set -eu
cd "$(dirname "$0")"
. ./.template.conf
NAME=""; REPO=""; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="${2:?}"; shift ;; --repo) REPO="${2:?}"; shift ;; --yes|-y) YES=1 ;;
  *) echo "unknown option $1"; exit 2 ;;
esac; shift; done
ask() { # ask VAR "question" default
  eval "cur=\${$1}"; [ -n "$cur" ] && return 0
  if [ $YES = 0 ] && [ -t 0 ]; then printf '%s [%s]: ' "$2" "$3"; read -r a; [ -n "$a" ] || a="$3"; else a="$3"; fi
  eval "$1=\$a"
}
GUESS=$(git remote get-url origin 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' || true)
ask REPO "GitHub repository (owner/name)" "${GUESS:-$OLD_REPO}"
echo "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { echo "✗ --repo must look like owner/name"; exit 1; }
ask NAME "Product name" "${REPO#*/}"
OWNER=${REPO%%/*}

# New names, derived the way `shipcrate init` derives them.
TOKEN=$(printf '%s' "$NAME" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9._-')
MODULE=$(printf '%s' "$TOKEN" | tr '.-' '__')
ENVP=$(printf '%s' "$TOKEN" | tr 'a-z.-' 'A-Z__')
CLASS=$(printf '%s' "$TOKEN" | awk -F'[-_.]' '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')
TAP="$OWNER/homebrew-$TOKEN"
BUNDLE="com.$(printf '%s' "$OWNER" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-').$TOKEN"

echo "→ Making it yours: $NAME (github.com/$REPO)"
# Longest, most specific strings first, so shorter ones don't break them.
SED=$(mktemp); trap 'rm -f "${SED:?}"' EXIT
add() { [ -n "$1" ] && printf 's|%s|%s|g\n' "$(printf '%s' "$1" | sed 's/[.[\*^$|]/\\&/g')" "$(printf '%s' "$2" | sed 's/[\\|&]/\\&/g')" >> "$SED"; return 0; }
add "${OLD_REPO%%/*}/$OLD_TOKEN/" "$OWNER/$TOKEN/"   # brew shorthand: owner/tap/name
add "$OLD_TAP" "$TAP"; add "$OLD_REPO" "$REPO"; add "$OLD_BUNDLE" "$BUNDLE"
add "$OLD_ENV" "$ENVP"; add "$OLD_CLASS" "$CLASS"; add "$OLD_MODULE" "$MODULE"
add "$OLD_NAME" "$NAME"; add "$OLD_TOKEN" "$TOKEN"
list() { if git rev-parse --git-dir >/dev/null 2>&1; then git ls-files --cached --others --exclude-standard; else find . -type f ! -path './.git/*' | sed 's#^\./##'; fi; }
list | grep -v -E '^(setup\.sh|\.template\.conf)$' | while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue            # text files only
  sed -f "$SED" "$f" > "$f.tmp" && { cmp -s "$f" "$f.tmp" && rm -f "$f.tmp" || { cat "$f.tmp" > "$f"; rm -f "$f.tmp"; }; }
done
# Rename files and folders named after the example (deepest first).
list | awk -F/ '{p=""; for(i=1;i<=NF;i++){p=(p==""?$i:p"/"$i); print p}}' | sort -u | awk '{print length, $0}' | sort -rn | cut -d' ' -f2- |
while IFS= read -r p; do
  b=$(basename "$p"); nb=$(printf '%s' "$b" | sed -f "$SED")
  [ "$b" != "$nb" ] && [ -e "$p" ] && mv "$p" "$(dirname "$p")/$nb" || true
done

# setup renamed text inside shipcrate's files: refresh the checksums `shipcrate sync` uses to spot your own edits
if [ -f .shipcrate/files.sha256 ]; then
  awk '{print $2}' .shipcrate/files.sha256 | while IFS= read -r f; do
    [ -f "$f" ] || continue; printf '%s  %s\n' "$( (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f") | cut -d' ' -f1)" "$f"
  done > .shipcrate/files.new && mv .shipcrate/files.new .shipcrate/files.sha256
fi
[ -d .git ] && sh scripts/install-hooks.sh >/dev/null && echo "✓ git hooks on (quick checks on commit, full checks on push)"
if [ $YES = 0 ] && [ -t 0 ]; then
  printf 'Turn on signed updates now (recommended; you can do it later with sh scripts/keygen.sh)? [Y/n] '
  read -r ok; case "$ok" in n|N|no) ;; *) sh scripts/keygen.sh ;; esac
fi
rm -f setup.sh .template.conf
git add -A 2>/dev/null || true
cat <<EOF

✓ $NAME is ready. Next:
  1. $FIRST_RUN
  2. Commit and push:  git commit -am "Set up $NAME" && git push
  3. First release:    sh scripts/release.sh 0.1.0 --dry-run   (then without --dry-run)
  If shipcrate helps, a ⭐ on https://github.com/simarpreetsingh-019/shipcrate helps others find it.
EOF
