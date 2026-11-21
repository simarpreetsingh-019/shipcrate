#!/bin/sh
# shipcrate in 60 seconds: a full release-and-update story, offline, on your machine.
#
#   sh examples/demo.sh            (needs: cargo, python3; nothing is published, nothing outside a temp folder changes)
#
# It builds the example CLI (examples/rust-cli) twice, as 1.0.0 and 1.1.0, "releases" 1.1.0 to a local web server
# with shipcrate's own scripts (checksums, latest.json), and then shows what a user of 1.0.0 sees:
#   1. the update notice          4. a message to every user (announce.sh)
#   2. a verified upgrade         5. a bad release pulled (yank.sh) and the user moved back
#   3. a rollback                 6. a tampered download refused
#                                 7. a forged manifest refused (signed updates)
set -eu
KIT=$(cd "$(dirname "$0")/.." && pwd)
EX="$KIT/examples/rust-cli"
for t in cargo python3; do command -v $t >/dev/null || { echo "This demo needs $t."; exit 1; }; done

W=$(mktemp -d); PID=""
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "${W:?}"; }
trap cleanup EXIT INT TERM
B=$(printf '\033[1m'); D=$(printf '\033[2m'); O=$(printf '\033[38;5;209m'); N=$(printf '\033[0m')
[ -t 1 ] || { B=""; D=""; O=""; N=""; }
step() { printf '\n%s━━ %s%s\n' "$O" "$*" "$N"; }
run() { printf '%s$ %s%s\n' "$D" "$*" "$N"; sh -c "$*"; }
pause() { [ -t 0 ] && [ -z "${NO_PAUSE:-}" ] && { printf '%s  (enter)%s' "$D" "$N"; read -r _; } || true; }

step "Building hello-ship 1.0.0 and 1.1.0 (the example CLI in examples/rust-cli), with signed updates on"
cp -R "$EX" "$W/src" && rm -rf "$W/src/target" "$W/src/dist"
export XDG_CONFIG_HOME="$W/config"     # the demo's signing key lives in the temp folder, not your ~/.config
SIGNED=0
if openssl version 2>/dev/null | grep -q '^OpenSSL [3-9]' || command -v node >/dev/null 2>&1; then
  ( cd "$W/src" && sh scripts/keygen.sh --no-secret >/dev/null ) && SIGNED=1 && echo "✓ signing key made (scripts/keygen.sh); its public key is built into hello-ship"
else echo "• (no OpenSSL 3 or Node here: running without signed updates)"; fi
resign() { if [ $SIGNED = 1 ]; then ( cd "$W/src" && sh scripts/sign.sh dist/latest.json >/dev/null ); fi; }
( cd "$W/src" && cargo build -q --release ) && mkdir -p "$W/bin" && cp "$W/src/target/release/hello-ship" "$W/bin/"
cp "$W/bin/hello-ship" "$W/hello-1.0.0"
( cd "$W/src" && sed -i.bak 's/^version = "1.0.0"/version = "1.1.0"/' Cargo.toml && cargo build -q --release )
echo "✓ built both"

step "Releasing 1.1.0 with shipcrate's scripts (to a local folder instead of GitHub)"
cd "$W/src"
. ./release.conf; . scripts/lib.sh
T=$(host_target); A=$(asset_for "$T")
case " $TARGETS " in *" $T "*) ;; *) echo "This machine ($T) isn't one of the example's targets."; exit 1 ;; esac
printf '## [1.1.0]\n- Friendlier greeting.\n' > CHANGELOG.md
run "sh scripts/build-release.sh $T | tail -1"
sh scripts/release-notes.sh 1.1.0 > dist/notes.md && sh scripts/manifest.sh 1.1.0 >/dev/null
PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
URL="http://127.0.0.1:$PORT"
sed "s#https://github.com/$REPO/releases/download/v1.1.0/#$URL/#" dist/latest.json > dist/served.json && mv dist/served.json dist/latest.json
resign
( cd dist && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & PID=$!
i=0; until curl -s "$URL/latest.json" >/dev/null 2>&1 || [ "$i" -ge 50 ]; do i=$((i+1)); sleep 0.1; done
echo "✓ published: $URL/latest.json  (SHA-256 $(cut -c1-16 "dist/$A.sha256")…)"

# The user's machine: their own cache folder, and the manifest pointed at our local "GitHub".
export XDG_CACHE_HOME="$W/cache" HELLO_SHIP_UPDATE_MANIFEST="$URL/latest.json"
cd "$W/bin"; pause

step "1 · A user on 1.0.0 runs the tool: one quiet line tells them about 1.1.0"
if [ -t 1 ] && [ -t 2 ]; then run "./hello-ship Ada"
else ./hello-ship Ada; echo "  (the notice only shows in an interactive terminal: never in scripts or CI)"; fi
pause

step "2 · They upgrade: download → verify SHA-256 → atomic swap (previous version kept)"
run "./hello-ship upgrade"
run "./hello-ship --version"
pause

step "3 · Changed their mind? Roll back"
run "./hello-ship upgrade --rollback"
run "./hello-ship --version"
pause

step "4 · You message every user, no release needed (scripts/announce.sh)"
( cd "$W/src" && sh scripts/announce.sh --file dist/latest.json "Maintenance Sunday 02:00 UTC" --level warning --url https://status.example.com >/dev/null )
resign
rm -rf "$W/cache"
if [ -t 1 ] && [ -t 2 ]; then run "./hello-ship Ada"
else printf '%s\n' "  (in a terminal, hello-ship prints:) ⚠️  NOTICE hello-ship: Maintenance Sunday 02:00 UTC · https://status.example.com"; fi
pause

step "5 · 1.1.0 turns out bad: yank it, and users on 1.1.0 are moved back to 1.0.0"
run "./hello-ship upgrade >/dev/null && ./hello-ship --version"
( cd "$W/src" && mkdir -p old && cp "$W/hello-1.0.0" old/hello-ship && chmod 755 old/hello-ship \
  && tar -czf "dist/old-$A" -C old hello-ship && SHA=$(sha256_of "dist/old-$A") \
  && python3 -I - "$URL" "$A" "$SHA" "$T" <<'PY'
import json, sys
url, a, sha, t = sys.argv[1:]
m = json.load(open("dist/latest.json"))
m.update(version="1.0.0", tag="v1.0.0", yanked=["1.1.0"])
m["assets"] = {t: {"name": a, "url": f"{url}/old-{a}", "sha256": sha}}
json.dump(m, open("dist/latest.json", "w"), indent=2)
PY
)
resign
rm -rf "$W/cache"
echo "  (latest.json now says: latest is 1.0.0, and 1.1.0 is yanked)"
run "./hello-ship upgrade"
run "./hello-ship --version"
pause

step "6 · Someone tampers with the download: the upgrade refuses it, nothing changes"
( cd "$W/src" && sed -i.bak 's/"version": "1.0.0"/"version": "9.9.9"/' dist/latest.json && echo junk >> "dist/old-$A" )
resign   # the publisher's real, signed manifest; only the file was changed on the way
run "./hello-ship upgrade || true"
run "./hello-ship --version"

if [ $SIGNED = 1 ]; then
  step "7 · An attacker rewrites latest.json to match their file: the signature check refuses it"
  ( cd "$W/src" && SHA=$(sha256_of "dist/old-$A") && sed -i.bak "s/\"sha256\": \"[0-9a-f]*\"/\"sha256\": \"$SHA\"/" dist/latest.json )
  echo "  (the checksum now matches the attacker's file, but they can't sign it without the private key)"
  run "./hello-ship upgrade || true"
  run "./hello-ship --version"
fi

printf '\n%s✓ That was shipcrate.%s Real releases do the same through GitHub: sh scripts/release.sh 1.1.0\n' "$B" "$N"
printf '  Set it up in your project: https://simarpreetsingh-019.github.io/shipcrate/quickstart/\n'
