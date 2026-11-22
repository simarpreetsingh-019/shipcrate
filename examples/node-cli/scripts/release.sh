#!/bin/sh
# Publish hello-node version $1:
#   guardrails → quality gate → set version → build → checksum → manifest → GitHub release → Homebrew tap → webhook
#   sh scripts/release.sh 1.2.0 ["extra notes"] [--security] [--rollout 10] [--yes] [--dry-run]
#   sh scripts/release.sh auto                  the version scripts/changelog.sh suggests from your commits
#   sh scripts/release.sh 1.3.0-beta.1          a pre-release: only the beta channel gets it, Homebrew stays put
# --rollout N offers it to N% of users first (widen with scripts/rollout.sh; Homebrew follows at 100%).
# --rollout-days D grows it from 0% (or --rollout N) to 100% over D days on its own: no follow-up commands.
# Safety rules when shipcrate's own code or the updater changed since the last stable release:
#   a beta of this version first (--skip-beta), scripts/update-path-test.sh passed for this commit (--skip-update-test),
#   and a timed rollout (SAFE_ROLLOUT_DAYS in release.conf, default 7; --full-rollout to skip).
# Every file name the last release had must still be there, so older copies can always update (--allow-renamed-assets).
# --dry-run builds and prints the notes but changes nothing. Asks before publishing unless --yes.
# Needs git and gh (`gh auth login`). Tokens never go in files: webhook settings come from the environment.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
V=""; NOTES=""; FLAGS=""; YES=0; DRY=0; ROLLOUT=100; ROLLOUT_DAYS=""; NEXT=""
SKIP_BETA=0; SKIP_UPT=0; FULL=0; RENAMED=0
for a in "$@"; do
  if [ "$NEXT" = rollout ]; then ROLLOUT="$a"; NEXT=""; continue; fi
  if [ "$NEXT" = days ]; then ROLLOUT_DAYS="$a"; NEXT=""; continue; fi
  case "$a" in
  --skip-beta) SKIP_BETA=1 ;; --skip-update-test) SKIP_UPT=1 ;; --full-rollout) FULL=1 ;; --allow-renamed-assets) RENAMED=1 ;;
  --yes|-y) YES=1 ;; --dry-run|-n) DRY=1 ;; --security) FLAGS="--security" ;; --rollout) NEXT=rollout ;; --rollout-days) NEXT=days ;;
  -*) echo "unknown flag $a"; exit 2 ;;
  *) if [ -z "$V" ]; then V="${a#v}"; else NOTES="$a"; fi ;;
esac; done
[ -n "$V" ] || { sed -n '2,10p' "$0"; exit 2; }
if [ "$V" = auto ]; then V=$(sh scripts/changelog.sh --version) || exit 1; echo "→ Version from your commits: $V"; fi
case "$ROLLOUT" in ''|*[!0-9]*) echo "✗ --rollout takes a percent (1-100)"; exit 2 ;; esac
case "$ROLLOUT_DAYS" in ""|[1-9]|[1-9][0-9]) ;; *) echo "✗ --rollout-days takes 1-99"; exit 2 ;; esac
if [ -n "$ROLLOUT_DAYS" ] && [ "$ROLLOUT" = 100 ]; then ROLLOUT=0; fi
export ROLLOUT_DAYS
PRE=0; case "$V" in *-*) PRE=1 ;; esac
say() { printf '%s\n' "$*"; }
die() { say "✗ $*"; exit 1; }
# In a dry run, guardrail failures are reported but don't stop the preview.
guard() { if [ $DRY = 1 ]; then say "• (dry run) would stop: $*"; else die "$*"; fi; }

# One release at a time from this folder (two terminals or agents releasing at once would race).
if [ $DRY = 0 ]; then
  LOCK="$(git rev-parse --git-dir 2>/dev/null || echo .)/shipcrate-release.lock"; HOST=$(hostname 2>/dev/null || echo here)
  if [ -f "$LOCK" ]; then
    read -r OPID OHOST OVER < "$LOCK" || true
    if [ "$OHOST" = "$HOST" ] && kill -0 "$OPID" 2>/dev/null; then die "another release ($OVER, pid $OPID) is running from this folder"; fi
    say "• removing a stale release lock ($OVER, pid $OPID on $OHOST)"
  fi
  printf '%s %s %s\n' "$$" "$HOST" "$V" > "$LOCK"; trap 'rm -f "$LOCK"' EXIT; trap 'rm -f "$LOCK"; exit 130' INT TERM
fi

say "→ Guardrails"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || die "version must look like 1.2.3 or 1.2.3-beta.1"
command -v gh >/dev/null || guard "install the GitHub CLI (brew install gh / winget install GitHub.cli) and run gh auth login"
gh auth status >/dev/null 2>&1 || guard "gh isn't signed in: run gh auth login"
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && die "tag v$V already exists"
LAST=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' | head -1 || true)   # skips moving tags like v1
if [ -n "$LAST" ]; then
  NEWEST=$(printf '%s\n%s\n' "${LAST#v}" "$V" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [ "$NEWEST" = "$V" ] && [ "${LAST#v}" != "$V" ] || [ $PRE = 1 ] || die "$V isn't newer than the last release ($LAST)"
fi
[ -z "$(git status --porcelain)" ] || guard "commit or stash your changes first"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
DEFAULT=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##'); DEFAULT=${DEFAULT:-main}
[ "$BRANCH" = "$DEFAULT" ] || guard "release from $DEFAULT (you're on $BRANCH)"
git fetch -q origin "$BRANCH" 2>/dev/null && [ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$BRANCH" 2>/dev/null)" ] && guard "$BRANCH differs from origin/$BRANCH: pull or push first"
grep -Eq "^## \[?v?$V\]?([ ]|$)" CHANGELOG.md 2>/dev/null || guard "CHANGELOG.md has no '## [$V]' section (it becomes \"What's new\"). Write one from your commits: sh scripts/changelog.sh --write"
if [ "${ALLOW_NO_CI:-}" != 1 ]; then
  CI=$(gh run list --commit "$(git rev-parse HEAD)" --workflow ci.yml --json conclusion -q '.[0].conclusion' 2>/dev/null || true)
  [ "$CI" = success ] || guard "CI hasn't passed for this commit (status: ${CI:-none}). Push and wait, or ALLOW_NO_CI=1 for a first release"
fi

# --- Safety rules for releases that change shipcrate's code or the updater
LAST_STABLE=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
SC=""
if [ -n "$LAST_STABLE" ]; then
  MARKED=$(grep -rls 'shipcrate:public-key' --include='*.rs' --include='*.py' --include='*.js' --include='*.ts' --include='*.swift' . 2>/dev/null | grep -v node_modules | sed 's#^\./##' || true)
  SC=$(git diff --name-only "$LAST_STABLE"..HEAD -- updater scripts tests/shipcrate $MARKED 2>/dev/null | tr '\n' ' ')
  [ "$(git show "$LAST_STABLE:release.conf" 2>/dev/null | grep '^SHIPCRATE_VERSION=')" != "$(grep '^SHIPCRATE_VERSION=' release.conf)" ] && SC="$SC release.conf(SHIPCRATE_VERSION)"
fi
if [ -n "$SC" ] && [ $PRE = 0 ]; then
  say "• shipcrate's code or the updater changed since $LAST_STABLE: $SC"
  if [ $SKIP_BETA = 0 ] && [ -z "$(git tag -l "v$V-*")" ]; then
    guard "release a beta of this version to testers first: sh scripts/release.sh $V-beta.1   (or --skip-beta)"
  fi
  OK=$(cat "$(git rev-parse --git-dir)/shipcrate-update-path-ok" 2>/dev/null || true)
  if [ $SKIP_UPT = 0 ] && [ "${OK%% *}" != "$(git rev-parse HEAD)" ]; then
    guard "prove old copies update to this one first: sh scripts/update-path-test.sh $V   (or --skip-update-test)"
  fi
  if [ $FULL = 0 ] && [ "$ROLLOUT" = 100 ] && [ -z "$ROLLOUT_DAYS" ]; then
    ROLLOUT_DAYS="${SAFE_ROLLOUT_DAYS:-7}"; ROLLOUT=0; export ROLLOUT_DAYS
    say "• safe rollout: 0% → 100% over $ROLLOUT_DAYS days (--full-rollout to send it to everyone now)"
  fi
fi
# Every download name the last release had must still exist (older updaters and installers look for them).
if [ -n "$LAST_STABLE" ] && [ $RENAMED = 0 ] && command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  WANT=""; for t in $TARGETS; do a=$(asset_for "$t"); WANT="$WANT $a $a.sha256"; done
  for n in $(gh release view "$LAST_STABLE" --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null); do
    case "$n" in *.tar.gz|*.tgz|*.zip|*.tar.gz.sha256|*.zip.sha256|*.tgz.sha256) case " $WANT " in *" $n "*) ;; *) guard "$LAST_STABLE had $n, but this release won't: older copies would break (--allow-renamed-assets if you really mean it)" ;; esac ;; esac
  done
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
  [ "$BUILD_WHERE" = local ] && ROLLOUT=$ROLLOUT sh scripts/manifest.sh "$V" $FLAGS >/dev/null && say "Manifest preview: dist/latest.json"
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
  ROLLOUT=$ROLLOUT sh scripts/manifest.sh "$V" $FLAGS
  set --; for f in dist/*; do case "$f" in dist/notes.md) ;; *) set -- "$@" "$f" ;; esac; done
  if [ $PRE = 1 ]; then set -- "$@" --prerelease; fi
  gh release create "v$V" "$@" --repo "$REPO" --title "$PRODUCT $V" --notes-file dist/notes.md
  sh scripts/channel.sh dist/latest.json || true
  sh scripts/notify.sh || true
else
  say "→ CI is building v$V on every target (.github/workflows/release.yml); waiting for the release…"
  i=0; rm -f dist/SHA256SUMS
  until gh release download "v$V" --repo "$REPO" --pattern SHA256SUMS --dir dist --clobber >/dev/null 2>&1; do
    i=$((i+1)); [ $i -lt 120 ] || die "the release workflow didn't publish in 30 min: check the Actions tab, then bump the tap by hand"
    sleep 15
  done
fi

if [ "$BUILD_WHERE" != local ] && { [ "$ROLLOUT" -lt 100 ] || [ -n "$ROLLOUT_DAYS" ]; }; then sh scripts/rollout.sh "$ROLLOUT" --yes ${ROLLOUT_DAYS:+--days "$ROLLOUT_DAYS"}; fi
if [ $PRE = 1 ]; then say "• pre-release: beta channel only; Homebrew and stable users stay on the current version"
elif [ -n "$ROLLOUT_DAYS" ]; then say "• timed rollout: $ROLLOUT% → 100% over $ROLLOUT_DAYS days, on its own. Homebrew is updated now (its users choose when to upgrade)."; sh scripts/tap.sh "$V"
elif [ "$ROLLOUT" -lt 100 ]; then say "• staged rollout at $ROLLOUT%: Homebrew follows when you run scripts/rollout.sh 100"
else sh scripts/tap.sh "$V"; fi
say "✓ Released $PRODUCT $V: https://github.com/$REPO/releases/tag/v$V"
say "  Verify: gh attestation verify <file> --repo $REPO"
