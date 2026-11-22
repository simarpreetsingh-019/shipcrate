#!/bin/sh
# Tests the release tooling end to end with a fake release on disk (file:// URLs): notes, manifest,
# checksums, and that install.sh installs a good build and refuses a tampered one.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/release.conf"; . "$ROOT/scripts/lib.sh"
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
fail() { echo "✗ $*"; exit 1; }

# A scratch copy of the project, so nothing real is touched.
mkdir -p "$W/p" && cp -R "$ROOT/scripts" "$ROOT/release.conf" "$W/p/"
[ -f "$ROOT/install.sh" ] && cp "$ROOT/install.sh" "$W/p/"
cd "$W/p"
printf '## [9.9.9]\n- a test change\n' > CHANGELOG.md

# asset names and targets
for t in $TARGETS; do a=$(asset_for "$t"); case "$a" in *"{target}"*|"") fail "asset_for $t gave '$a'" ;; esac; done
case "$(asset_for windows-x64)" in *.zip) ;; *) [ "$TYPE" = app ] || fail "windows assets should be .zip" ;; esac
[ "$(printf 'a"b\\c\nd' | json_string)" = '"a\"b\\c\nd"' ] || fail "json_string escaping"
for p in "1.10.0 1.10.0-beta.1" "1.10.0-beta.2 1.10.0-beta.1" "1.10.0-beta.10 1.10.0-beta.9" "1.10.0-rc.1 1.10.0-beta.3" "2.0.0 1.99.99"; do
  set -- $p; ver_gt "$1" "$2" || fail "ver_gt: $1 should be newer than $2"; ! ver_gt "$2" "$1" || fail "ver_gt: $2 should not be newer than $1"
done
! ver_gt 1.0.0 1.0.0 || fail "ver_gt: equal versions"

# a fake build for this machine (or the single target)
set -- $TARGETS; T=$1; for t in $TARGETS; do [ "$t" = "$(host_target)" ] && T=$t; done
A=$(asset_for "$T"); mkdir -p dist stage
if [ "$TYPE" = cli ]; then
  printf '#!/bin/sh\necho test-9.9.9\n' > "stage/$BINARY"; chmod 755 "stage/$BINARY"
  case "$A" in
    *.zip) if command -v zip >/dev/null; then (cd stage && zip -q "../dist/$A" "$BINARY")
           else powershell -NoProfile -Command "Compress-Archive -Path 'stage/$BINARY' -DestinationPath 'dist/$A'"; fi ;;
    *) tar -czf "dist/$A" -C stage "$BINARY" ;;
  esac
else
  mkdir -p "stage/x.app" && echo fake > "stage/x.app/f" && (cd stage && zip -qr "../dist/$A" x.app)
fi
(cd dist && printf '%s  %s\n' "$(sha256_of "$A")" "$A" > "$A.sha256")

sh scripts/release-notes.sh 9.9.9 --security > dist/notes.md
grep -q 'a test change' dist/notes.md || fail "notes miss the CHANGELOG section"
grep -q '\[security\]' dist/notes.md || fail "notes miss the security marker"
grep -q "$(cut -d' ' -f1 "dist/$A.sha256")" dist/notes.md || fail "notes miss the checksum"
sh scripts/manifest.sh 9.9.9 >/dev/null
for tool in python3 node ruby; do
  if command -v $tool >/dev/null; then
    case $tool in python3) python3 -I -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' dist/latest.json ;;
      node) node -e 'JSON.parse(require("fs").readFileSync(process.argv[1]))' dist/latest.json ;;
      ruby) ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' dist/latest.json ;; esac || fail "latest.json isn't valid JSON"
    break
  fi
done
grep -q '"security": true' dist/latest.json || fail "manifest should be marked security"
grep -q "\"$T\":" dist/latest.json || fail "manifest has no $T asset"
grep -q "$A" dist/SHA256SUMS || fail "SHA256SUMS missing $A"

# announcements: add (with quotes and backslashes), replace, clear; the manifest stays valid JSON
cp dist/latest.json dist/a.json
sh scripts/announce.sh --file dist/a.json 'Say "hi" \ there' --level warning --url https://example.com --below 9.9.9 >/dev/null
grep -q '"announcement":' dist/a.json || fail "announce.sh didn't add the announcement"
sh scripts/announce.sh --file dist/a.json "second" >/dev/null
[ "$(grep -c '"announcement":' dist/a.json)" = 1 ] || fail "announce.sh should replace, not stack"
if command -v python3 >/dev/null; then python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["announcement"]["message"]=="second"' dist/a.json || fail "announced manifest isn't valid JSON"; fi
sh scripts/announce.sh --file dist/a.json --clear >/dev/null
grep -q '"announcement":' dist/a.json && fail "--clear left the announcement"
sh scripts/announce.sh --file dist/a.json "x" --url http://insecure.example >/dev/null 2>&1 && fail "announce.sh accepted a non-https link"

# staged rollout and yanking edit the manifest and keep it valid JSON
valid() { if command -v python3 >/dev/null; then python3 -I -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); $2" "$1"; else true; fi; }
cp dist/latest.json dist/r.json
sh scripts/rollout.sh 25 --file dist/r.json >/dev/null
valid dist/r.json 'assert d["rollout"]==25' || fail "rollout.sh didn't set 25%"
sh scripts/rollout.sh 100 --file dist/r.json >/dev/null
valid dist/r.json 'assert "rollout" not in d' || fail "rollout 100 should remove the key"
sh scripts/rollout.sh 101 --file dist/r.json >/dev/null 2>&1 && fail "rollout.sh accepted 101%"
sh scripts/rollout.sh 0 --days 7 --file dist/r.json >/dev/null
valid dist/r.json 'assert d["rollout"]==0 and d["rollout_days"]==7' || fail "timed rollout not set"
sh scripts/rollout.sh 100 --file dist/r.json >/dev/null
valid dist/r.json 'assert "rollout" not in d and "rollout_days" not in d' || fail "rollout 100 should end a timed rollout"
sh scripts/yank.sh 9.9.8 --file dist/r.json >/dev/null && sh scripts/yank.sh 9.9.7 --file dist/r.json >/dev/null && sh scripts/yank.sh 9.9.8 --file dist/r.json >/dev/null
valid dist/r.json 'assert d["yanked"]==["9.9.8","9.9.7"], d["yanked"]' || fail "yank.sh list wrong"
if [ -f scripts/min-version.sh ]; then   # required update (older projects may not have it yet)
  sh scripts/min-version.sh 9.9.0 --file dist/r.json >/dev/null && valid dist/r.json 'assert d["min_version"]=="9.9.0"' || fail "min-version.sh didn't set it"
  sh scripts/min-version.sh --clear --file dist/r.json >/dev/null && valid dist/r.json 'assert "min_version" not in d' || fail "min-version.sh --clear didn't remove it"
  sh scripts/min-version.sh '1.0; rm -rf ~' --file dist/r.json >/dev/null 2>&1 && fail "min-version.sh accepted a non-version"
  MIN_VERSION=v9.0.0 sh scripts/manifest.sh 9.9.9 >/dev/null && valid dist/latest.json 'assert d["min_version"]=="9.0.0"' || fail "manifest.sh ignored MIN_VERSION"
  MIN_VERSION=10.0.0 sh scripts/manifest.sh 9.9.9 >/dev/null 2>&1 && fail "manifest.sh accepted a minimum newer than the release"
fi
ROLLOUT=10 sh scripts/manifest.sh 9.9.9 >/dev/null && valid dist/latest.json 'assert d["rollout"]==10' || fail "manifest.sh ignored ROLLOUT"
sh scripts/manifest.sh 9.9.9 >/dev/null

# install.sh with a local manifest: good install, then a tampered download must be refused.
# Safety first: only ever run shipcrate's own installer (checked BEFORE running it; a project's own install.sh is
# never executed), and only inside a sandbox: HOME, XDG folders and PATH point into the temp folder.
OURS=0
if [ -f install.sh ] && grep -q '^# shipcrate-installer: ' install.sh && grep -q 'unexpected download location' install.sh && grep -q 'MANIFEST_URL' install.sh; then OURS=1
elif [ -f install.sh ]; then echo "• install.sh isn't shipcrate's (kept as yours): not run by these tests"; fi
sandbox() {
  mkdir -p "$W/home/.local/bin" "$W/home/.config" "$W/home/.cache" "$W/home/.local/share"
  HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_CACHE_HOME="$W/home/.cache" XDG_DATA_HOME="$W/home/.local/share" \
    XDG_BIN_HOME="$W/home/.local/bin" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$@"
}
# (only when this machine is one of the release's platforms)
if [ $OURS = 1 ] && [ "$TYPE" = cli ] && { [ "$T" = "$(host_target)" ] || [ "$T" = any ]; } && [ "${T#windows}" = "$T" ]; then
  sed "s#https://github.com/$REPO/releases/download/v9.9.9/#file://$W/p/dist/#" dist/latest.json > dist/local.json
  sandbox env MANIFEST_URL="file://$W/p/dist/local.json" INSTALL_DIR="$W/bin" sh install.sh >/dev/null || fail "install.sh failed on a good release"
  [ "$("$W/bin/$BINARY")" = test-9.9.9 ] || fail "installed binary doesn't run"
  echo tampered >> "dist/$A"
  if sandbox env MANIFEST_URL="file://$W/p/dist/local.json" INSTALL_DIR="$W/bin2" sh install.sh >/dev/null 2>&1; then fail "install.sh accepted a tampered download"; fi
  [ ! -e "$W/bin2/$BINARY" ] || fail "tampered download was installed"
  # downloads from other hosts are refused with the default manifest
fi
# stats.sh: renders GitHub's download counts (from saved data here, no network)
printf 'v1.1.0\tfalse\tx 1.1.0\tx-macos-arm64.tar.gz\t40\t2026-11-20T10:00:00Z\nv1.1.0\tfalse\tx 1.1.0\tlatest.json\t300\t2026-11-20T10:00:00Z\nv1.2.0-beta.1\ttrue\tx\tx-linux-x64.tar.gz\t7\t2026-11-21T10:00:00Z\nchannel\ttrue\tc\tbeta.json\t12\t2026-11-21T10:00:00Z\n' > "$W/s.tsv"
OUT=$(SHIPCRATE_STATS_TSV="$W/s.tsv" sh scripts/stats.sh)
printf '%s' "$OUT" | grep -q 'v1.1.0.*stable.*40.*300' || fail "stats: stable row wrong"
printf '%s' "$OUT" | grep -q 'v1.2.0-beta.1.*beta.*7' || fail "stats: beta row wrong"
printf '%s' "$OUT" | grep -q 'beta channel checks (beta.json): 12' || fail "stats: beta checks wrong"
printf 'date,tag,file,count\n2026-11-20,v1.1.0,x-macos-arm64.tar.gz,10\n2026-11-21,v1.1.0,x-macos-arm64.tar.gz,25\n' > "$W/s.csv"
SHIPCRATE_STATS_TSV="$W/s.tsv" sh scripts/stats.sh --history "$W/s.csv" | grep -q '2026-11-21 *v1.1.0 *25 *+15' || fail "stats --history: per-day growth wrong"
XDG_CONFIG_HOME="$W/scfg" SHIPCRATE_STATS_TSV="$W/s.tsv" sh scripts/stats.sh --baseline >/dev/null
sed 's/\t40\t/\t46\t/' "$W/s.tsv" > "$W/s2.tsv"   # 6 more downloads after the zero point
OUT=$(XDG_CONFIG_HOME="$W/scfg" SHIPCRATE_STATS_TSV="$W/s2.tsv" sh scripts/stats.sh)
printf '%s' "$OUT" | grep -q 'Showing downloads since' || fail "stats: baseline not applied"
printf '%s' "$OUT" | grep -q 'v1.1.0.*stable *6 ' || fail "stats: baseline subtraction wrong"
XDG_CONFIG_HOME="$W/scfg" sh scripts/stats.sh --baseline-clear >/dev/null
XDG_CONFIG_HOME="$W/scfg" SHIPCRATE_STATS_TSV="$W/s2.tsv" sh scripts/stats.sh | grep -q 'v1.1.0.*stable *46 ' || fail "stats: --baseline-clear didn't restore totals"

# keygen.sh + sign.sh: keys with "/" and "+" land in release.conf and every updater file; signatures verify
if openssl version 2>/dev/null | grep -q '^OpenSSL [3-9]' || command -v node >/dev/null 2>&1; then
  K="$W/k"; mkdir -p "$K" && cp -R "$ROOT/scripts" "$ROOT/release.conf" "$K/" && mkdir -p "$K/updater"
  printf 'const KEY: &str = ""; // shipcrate:public-key\n' > "$K/updater/x.rs"
  i=0; slash=0
  while [ $i -lt 40 ] && [ $slash = 0 ]; do
    i=$((i+1)); rm -rf "$W/kcfg"
    ( cd "$K" && XDG_CONFIG_HOME="$W/kcfg" sh scripts/keygen.sh --no-secret >/dev/null ) || fail "keygen failed"
    PUBK=$(sed -n "s/^PUBLIC_KEY='\(.*\)'/\1/p" "$K/release.conf")
    grep -q "\"$PUBK\"" "$K/updater/x.rs" || fail "keygen didn't write the key ($PUBK) into the updater"
    case "$PUBK" in */*|*+*) slash=1 ;; esac
  done
  printf '{"version":"1.0.0"}\n' > "$K/m.json"
  ( cd "$K" && XDG_CONFIG_HOME="$W/kcfg" sh scripts/sign.sh m.json >/dev/null ) || fail "sign.sh failed"
  [ -s "$K/m.json.sig" ] || fail "no signature written"
fi

# changelog.sh: version and section from conventional commits, in a throwaway git repo
G="$W/g"; mkdir -p "$G" && cp -R "$ROOT/scripts" "$ROOT/release.conf" "$G/" && cd "$G"
git init -q && git config user.email t@example.invalid && git config user.name t && git config commit.gpgsign false
printf '# Changelog\n\n## [1.2.3] - 2026-01-01\n- old\n' > CHANGELOG.md
git add -A && git commit -qm "chore: init" --no-verify && git tag v1.2.3
c() { git commit -q --allow-empty --no-verify -m "$1"; }
c "fix: crash on empty input"
git tag v1   # a moving major tag (GitHub Action style) must not count as the last release
[ "$(sh scripts/changelog.sh --version)" = 1.2.4 ] || fail "fix should be a patch"
c "feat(cli): add --json output"; c "docs: typo"; c "fix(security): reject bad paths"
[ "$(sh scripts/changelog.sh --version)" = 1.3.0 ] || fail "feat should be a minor"
sh scripts/changelog.sh | grep -q '### Security' || fail "no Security section"
sh scripts/changelog.sh | grep -q 'Typo' && fail "docs commits should be left out"
c "feat!: new config format"
[ "$(sh scripts/changelog.sh --version)" = 2.0.0 ] || fail "breaking should be a major"
sh scripts/changelog.sh --write >/dev/null && grep -q '^## \[2.0.0\]' CHANGELOG.md && grep -q 'Breaking' CHANGELOG.md || fail "--write didn't add the section"
[ "$(grep -n '^## \[' CHANGELOG.md | head -1 | cut -d'[' -f2 | cut -d']' -f1)" = 2.0.0 ] || fail "new section should be on top"
# Betas name the next stable version: after 2.0.0, 2.1.0-beta.2 + a fix → 2.1.0 (not 2.0.1); a beta of an older
# version is ignored; a bigger bump than the beta wins.
git add -A && git commit -qm "docs: changelog" --no-verify && git tag v2.0.0
c "fix: one"; git tag v2.1.0-beta.1; c "fix: two"; git tag v2.1.0-beta.2; c "fix: three"
[ "$(sh scripts/changelog.sh --version)" = 2.1.0 ] || fail "after 2.1.0 betas, a fix should suggest 2.1.0, got $(sh scripts/changelog.sh --version)"
git tag v1.9.9-beta.1
[ "$(sh scripts/changelog.sh --version)" = 2.1.0 ] || fail "a beta of an older version changed the suggestion"
c "feat!: breaking"
[ "$(sh scripts/changelog.sh --version)" = 3.0.0 ] || fail "a breaking change after 2.1.0 betas should suggest 3.0.0"
git tag -d v2.0.0 v2.1.0-beta.1 v2.1.0-beta.2 v1.9.9-beta.1 >/dev/null   # the tests below expect v1.2.3 as the last release
# release.sh: one release at a time (a second one is refused while the first runs)
printf '%s %s %s\n' "$$" "$(hostname 2>/dev/null || echo here)" "9.9.9" > "$(git rev-parse --git-dir)/shipcrate-release.lock"
OUT=$(sh scripts/release.sh 9.9.10 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -q 'another release' || fail "release.sh didn't refuse a second release at the same time"
rm -f "$(git rev-parse --git-dir)/shipcrate-release.lock"
# Safety rules: when shipcrate's code changed since the last stable, a stable release needs a beta first,
# a passing update-path test, and gets a timed rollout
sed "s/^SHIPCRATE_VERSION=.*/SHIPCRATE_VERSION='99.0.0'/" release.conf > release.conf.new && mv release.conf.new release.conf
grep -q '^SHIPCRATE_VERSION=' release.conf || printf "SHIPCRATE_VERSION='99.0.0'\n" >> release.conf
git add -A && git commit -qm "chore: bump shipcrate" --no-verify
OUT=$(sh scripts/release.sh 1.3.0 --dry-run 2>&1 || true)
printf '%s' "$OUT" | grep -q 'release a beta of this version' || fail "release.sh didn't ask for a beta first"
printf '%s' "$OUT" | grep -q 'update-path-test.sh 1.3.0' || fail "release.sh didn't ask for the update-path test"
printf '%s' "$OUT" | grep -q 'safe rollout' || fail "release.sh didn't default to a timed rollout"
OUT=$(sh scripts/release.sh 1.3.0-beta.1 --dry-run 2>&1 || true)
printf '%s' "$OUT" | grep -q 'release a beta of this version' && fail "a beta shouldn't need a beta"
cd "$W/p"
echo "release scripts and installer: ok"
