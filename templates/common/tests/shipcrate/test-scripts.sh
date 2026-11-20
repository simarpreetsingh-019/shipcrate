#!/bin/sh
# Tests the release tooling end to end with a fake release on disk (file:// URLs): notes, manifest,
# checksums, and that install.sh installs a good build and refuses a tampered one.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/release.conf"; . "$ROOT/scripts/lib.sh"
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
fail() { echo "✗ $*"; exit 1; }

# A scratch copy of the project, so nothing real is touched.
mkdir -p "$W/p" && cp -R "$ROOT/scripts" "$ROOT/release.conf" "$W/p/" && cp "$ROOT/install.sh" "$W/p/"
cd "$W/p"
printf '## [9.9.9]\n- a test change\n' > CHANGELOG.md

# asset names and targets
for t in $TARGETS; do a=$(asset_for "$t"); case "$a" in *"{target}"*|"") fail "asset_for $t gave '$a'" ;; esac; done
case "$(asset_for windows-x64)" in *.zip) ;; *) [ "$TYPE" = app ] || fail "windows assets should be .zip" ;; esac
[ "$(printf 'a"b\\c\nd' | json_string)" = '"a\"b\\c\nd"' ] || fail "json_string escaping"

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

# install.sh with a local manifest: good install, then a tampered download must be refused
# (only when this machine is one of the release's platforms)
if [ "$TYPE" = cli ] && { [ "$T" = "$(host_target)" ] || [ "$T" = any ]; } && [ "${T#windows}" = "$T" ]; then
  sed "s#https://github.com/$REPO/releases/download/v9.9.9/#file://$W/p/dist/#" dist/latest.json > dist/local.json
  MANIFEST_URL="file://$W/p/dist/local.json" INSTALL_DIR="$W/bin" sh install.sh >/dev/null || fail "install.sh failed on a good release"
  [ "$("$W/bin/$BINARY")" = test-9.9.9 ] || fail "installed binary doesn't run"
  echo tampered >> "dist/$A"
  if MANIFEST_URL="file://$W/p/dist/local.json" INSTALL_DIR="$W/bin2" sh install.sh >/dev/null 2>&1; then fail "install.sh accepted a tampered download"; fi
  [ ! -e "$W/bin2/$BINARY" ] || fail "tampered download was installed"
  # downloads from other hosts are refused with the default manifest
  grep -q 'unexpected download location' install.sh || fail "install.sh lost its host check"
fi
echo "release scripts and installer: ok"
