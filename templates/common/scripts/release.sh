#!/bin/sh
# Publish {{PRODUCT}} version $1:
#   guardrails → quality gate → set version → build → checksum → manifest → GitHub release → Homebrew tap → webhook
#   sh scripts/release.sh 1.2.0 ["extra notes"] [--security] [--yes] [--dry-run]
# --dry-run builds and prints the notes but changes nothing. Asks before publishing unless --yes.
# Needs git and gh (`gh auth login`). Tokens never go in files: webhook settings come from the environment.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
V=""; NOTES=""; FLAGS=""; YES=0; DRY=0
for a in "$@"; do case "$a" in
  --yes|-y) YES=1 ;; --dry-run|-n) DRY=1 ;; --security) FLAGS="--security" ;;
  -*) echo "unknown flag $a"; exit 2 ;;
  *) if [ -z "$V" ]; then V="${a#v}"; else NOTES="$a"; fi ;;
esac; done
[ -n "$V" ] || { sed -n '2,6p' "$0"; exit 2; }
say() { printf '%s\n' "$*"; }
die() { say "✗ $*"; exit 1; }
# In a dry run, guardrail failures are reported but don't stop the preview.
guard() { if [ $DRY = 1 ]; then say "• (dry run) would stop: $*"; else die "$*"; fi; }

say "→ Guardrails"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || die "version must look like 1.2.3 or 1.2.3-beta.1"
command -v gh >/dev/null || die "install the GitHub CLI (brew install gh / winget install GitHub.cli) and run gh auth login"
gh auth status >/dev/null 2>&1 || guard "gh isn't signed in: run gh auth login"
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && die "tag v$V already exists"
LAST=$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1)
if [ -n "$LAST" ]; then
  NEWEST=$(printf '%s\n%s\n' "${LAST#v}" "$V" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [ "$NEWEST" = "$V" ] && [ "${LAST#v}" != "$V" ] || die "$V isn't newer than the last release ($LAST)"
fi
[ -z "$(git status --porcelain)" ] || guard "commit or stash your changes first"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
DEFAULT=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##'); DEFAULT=${DEFAULT:-main}
[ "$BRANCH" = "$DEFAULT" ] || guard "release from $DEFAULT (you're on $BRANCH)"
git fetch -q origin "$BRANCH" 2>/dev/null && [ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$BRANCH" 2>/dev/null)" ] && guard "$BRANCH differs from origin/$BRANCH: pull or push first"
grep -Eq "^## \[?v?$V\]?([ ]|$)" CHANGELOG.md 2>/dev/null || guard "CHANGELOG.md has no '## [$V]' section (it becomes \"What's new\")"
if [ "${ALLOW_NO_CI:-}" != 1 ]; then
  CI=$(gh run list --commit "$(git rev-parse HEAD)" --workflow ci.yml --json conclusion -q '.[0].conclusion' 2>/dev/null || true)
  [ "$CI" = success ] || guard "CI hasn't passed for this commit (status: ${CI:-none}). Push and wait, or ALLOW_NO_CI=1 for a first release"
fi

say "→ Quality gate (release mode: security checks are required, not optional)"
sh scripts/check.sh --release || guard "the gate failed: fix it before releasing"

say "→ Setting version $V"
export V; [ $DRY = 1 ] || sh -c "$VERSION_CMD"

if [ "$BUILD_WHERE" = local ]; then
  say "→ Building"
  rm -f dist/*.sha256
  for t in $TARGETS; do
    case "$t" in any|macos|"$(host_target)") sh scripts/build-release.sh "$t" ;; *) say "• $t: built only in CI (BUILD_WHERE=ci); skipped here" ;; esac
  done
fi
mkdir -p dist
sh scripts/release-notes.sh "$V" "$NOTES" $FLAGS > dist/notes.md
say ""; say "──── Release notes for v$V ────"; cat dist/notes.md; say "───────────────────────────────"
if [ $DRY = 1 ]; then
  [ "$BUILD_WHERE" = local ] && sh scripts/manifest.sh "$V" $FLAGS >/dev/null && say "Manifest preview: dist/latest.json"
  say "Dry run: nothing was committed, tagged, pushed or published."; exit 0
fi
if [ $YES = 0 ]; then
  printf 'Publish %s %s to github.com/%s%s? [y/N] ' "$PRODUCT" "$V" "$REPO" "$([ "$TAP_REPO" = none ] || echo " and bump $TAP_REPO")"
  read -r ok; case "$ok" in y|Y|yes) ;; *) die "cancelled, nothing published (version files were edited: git checkout . to undo)";; esac
fi

git add -A && (git commit -qm "Release $V" || true)
git tag -a "v$V" -m "$PRODUCT $V"
git push -q && git push -q origin "v$V"

if [ "$BUILD_WHERE" = local ]; then
  sh scripts/manifest.sh "$V" $FLAGS
  set --; for f in dist/*; do case "$f" in dist/notes.md) ;; *) set -- "$@" "$f" ;; esac; done
  gh release create "v$V" "$@" --repo "$REPO" --title "$PRODUCT $V" --notes-file dist/notes.md
  sh scripts/notify.sh || true
else
  say "→ CI is building v$V on every target (.github/workflows/release.yml); waiting for the release…"
  i=0; rm -f dist/SHA256SUMS
  until gh release download "v$V" --repo "$REPO" --pattern SHA256SUMS --dir dist --clobber >/dev/null 2>&1; do
    i=$((i+1)); [ $i -lt 120 ] || die "the release workflow didn't publish in 30 min: check the Actions tab, then bump the tap by hand"
    sleep 15
  done
fi

if [ "$TAP_REPO" != none ]; then
  say "→ Bumping $TAP_REPO ($TAP_FILE)"
  if ! gh repo view "$TAP_REPO" >/dev/null 2>&1; then
    say "• Tap $TAP_REPO doesn't exist. Ask the owner, create it (gh repo create $TAP_REPO --public), copy packaging/homebrew/$(basename "$TAP_FILE") to $TAP_FILE, then rerun."
  else
    TAP=$(mktemp -d); trap 'rm -rf "${TAP:?}"' EXIT
    gh repo clone "$TAP_REPO" "$TAP" -- -q
    if [ ! -f "$TAP/$TAP_FILE" ]; then mkdir -p "$TAP/$(dirname "$TAP_FILE")"; cp "packaging/homebrew/$(basename "$TAP_FILE")" "$TAP/$TAP_FILE"; git -C "$TAP" add "$TAP_FILE"; fi
    F="$TAP/$TAP_FILE"
    sed -E "s/^  version \".*\"/  version \"$V\"/" "$F" > "$F.new" && mv "$F.new" "$F"
    for t in $TARGETS; do
      a=$(asset_for "$t"); sha=$(awk -v a="$a" '$2==a || $2=="*"a {print $1}' dist/SHA256SUMS)
      [ -n "$sha" ] || continue
      sed -E "s/sha256 \"[0-9a-f]*\"( *# shipcrate:$t)$/sha256 \"$sha\"\1/" "$F" > "$F.new" && mv "$F.new" "$F"
    done
    git -C "$TAP" commit -qam "$TOKEN $V" && git -C "$TAP" push -q
  fi
fi
say "✓ Released $PRODUCT $V: https://github.com/$REPO/releases/tag/v$V"
say "  Verify: gh attestation verify <file> --repo $REPO"
