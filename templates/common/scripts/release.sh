#!/bin/sh
# Publish {{PRODUCT}} version $1:  gate → set version → build → package → checksum → GitHub release → Homebrew tap.
#   sh scripts/release.sh 1.2.0 ["extra notes"] [--security] [--yes] [--dry-run]
# --dry-run builds and prints the notes but changes nothing (no commit, tag, push, release or tap).
# Asks before publishing unless --yes. Needs: git, gh (signed in with `gh auth login`). No tokens in files.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
V=""; NOTES=""; FLAGS=""; YES=0; DRY=0
for a in "$@"; do case "$a" in
  --yes|-y) YES=1 ;; --dry-run|-n) DRY=1 ;; --security) FLAGS="--security" ;;
  -*) echo "unknown flag $a"; exit 2 ;;
  *) if [ -z "$V" ]; then V="${a#v}"; else NOTES="$a"; fi ;;
esac; done
[ -n "$V" ] || { sed -n '2,5p' "$0"; exit 2; }
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' || { echo "✗ version must look like 1.2.3"; exit 2; }
say() { printf '%s\n' "$*"; }
die() { say "✗ $*"; exit 1; }

command -v gh >/dev/null || die "install the GitHub CLI (brew install gh) and run gh auth login"
[ $DRY = 1 ] || gh auth status >/dev/null 2>&1 || die "gh isn't signed in: run gh auth login"
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && die "tag v$V already exists"
[ -z "$(git status --porcelain)" ] || [ $DRY = 1 ] || die "commit or stash your changes first"

say "→ Quality gate"
sh scripts/check.sh --release || [ $DRY = 1 ] || die "the gate failed: fix it before releasing"

say "→ Setting version $V"
export V; [ $DRY = 1 ] || sh -c "$VERSION_CMD"

if [ "$BUILD_WHERE" = local ]; then
  say "→ Building $ASSET"
  sh scripts/build-release.sh
fi
BODY=$(sh scripts/release-notes.sh "$V" "$NOTES" $FLAGS)
say ""; say "──── Release notes for v$V ────"; say "$BODY"; say "───────────────────────────────"
if [ $DRY = 1 ]; then say "Dry run: nothing was committed, tagged, pushed or published."; exit 0; fi
if [ $YES = 0 ]; then
  printf 'Publish %s %s to github.com/%s%s? [y/N] ' "$PRODUCT" "$V" "$REPO" "$([ "$TAP_REPO" = none ] || echo " and bump $TAP_REPO")"
  read -r ok; case "$ok" in y|Y|yes) ;; *) die "cancelled, nothing published (version files were edited: git checkout . to undo)";; esac
fi

git add -A && (git commit -qm "Release $V" || true)
git tag -a "v$V" -m "$PRODUCT $V"
git push -q && git push -q origin "v$V"

if [ "$BUILD_WHERE" = local ]; then
  printf '%s\n' "$BODY" > dist/notes.md
  gh release create "v$V" "dist/$ASSET" "dist/$ASSET.sha256" --repo "$REPO" --title "$PRODUCT $V" --notes-file dist/notes.md
  SHA=$(cut -d' ' -f1 "dist/$ASSET.sha256")
else
  say "→ CI is building v$V (.github/workflows/release.yml); waiting for $ASSET.sha256…"
  SHA=""; i=0
  while [ -z "$SHA" ] && [ $i -lt 120 ]; do
    sleep 15; i=$((i+1))
    SHA=$(gh release download "v$V" --repo "$REPO" --pattern "$ASSET.sha256" --output - 2>/dev/null | cut -d' ' -f1 || true)
  done
  [ -n "$SHA" ] || die "the release workflow didn't publish in 30 min: check the Actions tab, then bump the tap by hand"
fi

if [ "$TAP_REPO" != none ]; then
  say "→ Bumping $TAP_REPO ($TAP_FILE)"
  if ! gh repo view "$TAP_REPO" >/dev/null 2>&1; then
    say "• Tap $TAP_REPO doesn't exist. Create it (gh repo create $TAP_REPO --public), copy packaging/homebrew/$(basename "$TAP_FILE") to $TAP_FILE, then rerun."
  else
    TAP=$(mktemp -d); trap 'rm -rf "${TAP:?}"' EXIT
    gh repo clone "$TAP_REPO" "$TAP" -- -q
    if [ ! -f "$TAP/$TAP_FILE" ]; then mkdir -p "$TAP/$(dirname "$TAP_FILE")"; cp "packaging/homebrew/$(basename "$TAP_FILE")" "$TAP/$TAP_FILE"; git -C "$TAP" add "$TAP_FILE"; fi
    sed -E "s/^  version \".*\"/  version \"$V\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/$TAP_FILE" > "$TAP/.new" && mv "$TAP/.new" "$TAP/$TAP_FILE"
    git -C "$TAP" commit -qam "$TOKEN $V" && git -C "$TAP" push -q
  fi
fi
say "✓ Released $PRODUCT $V: https://github.com/$REPO/releases/tag/v$V"
