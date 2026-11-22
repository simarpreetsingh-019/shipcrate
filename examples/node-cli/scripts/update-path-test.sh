#!/bin/sh
# Rule 3: before a stable release, prove that a copy people already have updates itself to the new version.
#   sh scripts/update-path-test.sh <new-version> [--from vX.Y.Z | --old FILE]   (--old: a local old archive)
# It downloads the old release (default: the newest stable) from GitHub, builds the new version from this
# working tree in a temp copy, serves it from this machine (http://127.0.0.1, nothing published), and lets the
# OLD copy's own updater upgrade itself: download → checksum (and signature) → swap → the new version runs.
# CLI: runs `<binary> upgrade`. macOS app: runs `<App> --update-now` (your app needs that flag) and checks the
# swapped app's version; the relaunched test app is closed afterwards.
# Success is recorded for this commit, and release.sh asks for it when shipcrate's code or the updater changed.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
NEW="${1:?usage: update-path-test.sh <new-version> [--from vX.Y.Z]}"; NEW="${NEW#v}"; shift
FROM=""; OLDF=""; while [ $# -gt 0 ]; do case "$1" in --from) FROM="${2:?}"; shift ;; --old) OLDF="${2:?}"; shift ;; *) echo "unknown option $1"; exit 2 ;; esac; shift; done
[ -z "$OLDF" ] || { [ -f "$OLDF" ] || { echo "✗ no such file: $OLDF"; exit 1; }; OLDF=$(cd "$(dirname "$OLDF")" && pwd)/$(basename "$OLDF"); FROM="${FROM:-local}"; }
die() { echo "✗ $*" >&2; exit 1; }
[ -n "$FROM" ] || FROM=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
[ -n "$FROM" ] || { echo "• no earlier stable release: nothing to update from (first release)"; exit 0; }
T=$(host_target); [ "$TYPE" = app ] && T=macos
case " $TARGETS " in *" $T "*|*" any "*) ;; *) die "this machine ($T) isn't one of TARGETS ($TARGETS)" ;; esac
[ "$TARGETS" = any ] && T=any
A=$(asset_for "$T"); ENVP=$(printf '%s' "$TOKEN" | tr 'a-z.-' 'A-Z__')
W=$(mktemp -d); PID=""
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "${W:?}"; }
trap cleanup EXIT INT TERM
echo "→ Update path: $FROM (from GitHub) → $NEW (built here, served locally)"

# 1. the old copy, exactly as users have it
mkdir -p "$W/old"
if [ -n "$OLDF" ]; then cp "$OLDF" "$W/old/$A"
else gh release download "$FROM" --repo "$REPO" --pattern "$A" --dir "$W/old" >/dev/null || die "couldn't download $A from $FROM"; fi

# 2. the new version, built from this working tree in a temp copy (your tree is not touched)
mkdir -p "$W/src" && git ls-files -z | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp -p "$2" "$1/$2"' _ "$W/src" {}
( cd "$W/src" && export V="$NEW" && sh -c "$VERSION_CMD" && sh scripts/build-release.sh "$T" >/dev/null ) || die "couldn't build $NEW"
printf '## [%s]\n- update path test\n' "$NEW" > "$W/src/dist/notes.md"
( cd "$W/src" && sh scripts/manifest.sh "$NEW" >/dev/null ) || die "couldn't write the manifest (signing key missing?)"
PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
sed "s#https://github.com/$REPO/releases/download/v$NEW/#http://127.0.0.1:$PORT/#" "$W/src/dist/latest.json" > "$W/src/dist/l.json" && mv "$W/src/dist/l.json" "$W/src/dist/latest.json"
[ -n "${PUBLIC_KEY:-}" ] && ( cd "$W/src" && sh scripts/sign.sh dist/latest.json >/dev/null )
( cd "$W/src/dist" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & PID=$!
i=0; until curl -s "http://127.0.0.1:$PORT/latest.json" >/dev/null 2>&1 || [ "$i" -ge 50 ]; do i=$((i+1)); sleep 0.1; done
MANIFEST="http://127.0.0.1:$PORT/latest.json"

# 3. let the old copy update itself
if [ "$TYPE" = cli ]; then
  mkdir -p "$W/bin" && tar -xzf "$W/old/$A" -C "$W/old" 2>/dev/null || (cd "$W/old" && unzip -q "$A")
  cp "$W/old/$BINARY" "$W/bin/$BINARY" && chmod 755 "$W/bin/$BINARY"
  env "${ENVP}_UPDATE_MANIFEST=$MANIFEST" XDG_CACHE_HOME="$W/cache" "$W/bin/$BINARY" upgrade || die "the old copy's upgrade failed"
  OUT=$("$W/bin/$BINARY" --version 2>&1 || true)
  printf '%s' "$OUT" | grep -q "$NEW" || die "after upgrading, the binary says: $OUT (expected $NEW). Old copies without shipcrate's updater can't use a local manifest: try --from <a newer tag>"
else
  ditto -x -k "$W/old/$A" "$W/old/x" && APP=$(find "$W/old/x" -maxdepth 1 -name '*.app' | head -1)
  [ -n "$APP" ] || die "no .app in $A"
  EXE=$(defaults read "$APP/Contents/Info" CFBundleExecutable)
  # The test app shares preferences with your real copy (same bundle ID): save them now, put them back after.
  defaults export "$BUNDLE_ID" "$W/prefs.plist" 2>/dev/null || true
  restore_prefs() { [ -f "$W/prefs.plist" ] && defaults import "$BUNDLE_ID" "$W/prefs.plist" 2>/dev/null || true; }
  env "${ENVP}_UPDATE_MANIFEST=$MANIFEST" "$APP/Contents/MacOS/$EXE" --update-now >/dev/null 2>&1 &
  i=0; until [ "$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)" = "$NEW" ] || [ "$i" -ge 120 ]; do i=$((i+1)); sleep 1; done
  GOT=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo none)
  sleep 3; pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true      # close the relaunched test copy
  restore_prefs
  [ "$GOT" = "$NEW" ] || die "the old app didn't swap itself to $NEW (it shows $GOT). It needs shipcrate's updater and a --update-now flag; for apps released before that, use --from <a newer tag>"
  codesign --verify --deep --strict "$APP" 2>/dev/null || die "the swapped app's signature is broken"
fi
mkdir -p "$(git rev-parse --git-dir)" && printf '%s %s %s\n' "$(git rev-parse HEAD)" "$NEW" "$FROM" > "$(git rev-parse --git-dir)/shipcrate-update-path-ok"
echo "✓ $FROM updated itself to $NEW (download, checksum$([ -n "${PUBLIC_KEY:-}" ] && echo ', signature'), swap, runs). Recorded for this commit."
