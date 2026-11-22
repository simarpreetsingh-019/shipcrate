#!/bin/sh
# Runs `shipcrate init` for every product type and language into scratch folders and checks the output:
# no unfilled placeholders, shell syntax, YAML, Ruby (formula/cask), and each updater snippet compiles/parses
# where its toolchain is installed. Also checks --dry-run writes nothing and existing files aren't overwritten.
set -u
cd "$(dirname "$0")/.."
KIT=$(pwd); FAIL=0
ok() { printf '  ✔ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); }
check() { d="$1"; shift; if "$@" >/dev/null 2>"$WORK/err"; then ok "$d"; else bad "$d"; sed 's/^/      /' "$WORK/err" | head -8; fi; }
has() { command -v "$1" >/dev/null 2>&1; }
WORK=$(mktemp -d); trap 'rm -rf "${WORK:?}"' EXIT

for combo in "app swift Thermo" "cli rust msh" "cli python pytool" "cli node nodetool" "cli swift swiftcli" "cli rust wincli windows-x64_linux-x64"; do
  set -- $combo; TYPE=$1; L=$2; N=$3; TG=$(echo "${4:-}" | tr _ ' '); D="$WORK/$N"; mkdir -p "$D"
  echo "• init $N ($TYPE, $L${TG:+, $TG})"
  check "init runs" sh "$KIT/bin/shipcrate" init "$D" --yes --name "$N" --type "$TYPE" --lang "$L" --repo "example/$N" --desc "Test $N" ${TG:+--targets "$TG"}
  left=$(grep -rnoE '\{\{[A-Z_]+\}\}' "$D" || true); [ -z "$left" ] && ok "no unfilled placeholders" || bad "unfilled placeholders: $left"
  for f in $(find "$D" -name '*.sh') "$D"/.githooks/*; do check "sh -n ${f#$D/}" sh -n "$f"; done
  ( . "$D/release.conf" ) && ok "release.conf sources" || bad "release.conf doesn't source"
  for f in "$D"/.github/workflows/*.yml; do check "YAML ${f#$D/}" ruby -ryaml -e 'YAML.load_file(ARGV[0]) or exit 1' "$f"; done
  for f in "$D"/packaging/homebrew/*.rb; do check "ruby -c ${f#$D/}" ruby -c "$f"; done
  [ -f "$D/updater/update_check.py" ] && check "python compiles updater" python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$D/updater/update_check.py"
  [ -f "$D/updater/update-check.js" ] && has node && check "node --check updater" node --check "$D/updater/update-check.js"
  if [ -f "$D/updater/update.rs" ] && has rustc; then
    check "rustc: updater compiles + tests pass" sh -c "rustc --edition 2021 --test -o '$WORK/t-$N' '$D/updater/update.rs' && '$WORK/t-$N' -q"
  fi
  if [ -f "$D/updater/Updater.swift" ] && has swiftc; then
    if [ "$(uname)" = Darwin ]; then check "swiftc -typecheck updater" swiftc -typecheck "$D/updater/Updater.swift"
    else check "swiftc -parse updater" swiftc -parse "$D/updater/Updater.swift"; fi
  fi
  [ "$N" = wincli ] && { [ -f "$D/install.ps1" ] && ok "Windows target gets install.ps1" || bad "no install.ps1 for a Windows target"; }
  [ "$N" = msh ] && { grep -q 'shipcrate:linux-arm64' "$D/packaging/homebrew/msh.rb" && ok "formula has per-platform checksums" || bad "formula lacks per-platform checksums"; }
  if has pwsh && [ -f "$D/install.ps1" ]; then check "PowerShell parses install.ps1" pwsh -NoProfile -File "$KIT/tests/parse-ps1.ps1" "$D/install.ps1"; fi
  # The tests shipcrate ships into the project must pass in the fresh project.
  ( cd "$D" && git init -q && git add -A ) && check "shipped tests pass (tests/shipcrate/run.sh)" sh "$D/tests/shipcrate/run.sh"
  ( cd "$D" && mkdir -p dist && echo "abc  x" > "dist/$(. ./release.conf; echo "$ASSET").sha256" && printf '## [1.0.0]\n- thing\n' > CHANGELOG.md &&
    sh scripts/release-notes.sh 1.0.0 --security | grep -q '\[security\]' && sh scripts/release-notes.sh 1.0.0 | grep -q 'thing' ) \
    && ok "release notes: What's new + security marker" || bad "release notes"
done

echo "• safety"
grep -qx 'dist/' "$WORK/msh/.gitignore" && ok "dist/ is git-ignored" || bad "dist/ not in .gitignore"
D="$WORK/safe"; mkdir -p "$D"
sh bin/shipcrate init "$D" --dry-run --yes --name s --type cli --lang rust --repo e/s >/dev/null
[ -z "$(ls -A "$D")" ] && ok "--dry-run writes nothing" || bad "--dry-run wrote files"
echo keep > "$D/CHANGELOG.md"
sh bin/shipcrate init "$D" --yes --name s --type cli --lang rust --repo e/s >/dev/null
[ "$(cat "$D/CHANGELOG.md")" = keep ] && ok "existing files are not overwritten" || bad "overwrote an existing file"
sh bin/shipcrate init "$D" --yes --name s --type cli --lang ruby --repo e/s >/dev/null 2>&1 && bad "accepted bad --lang" || ok "rejects unknown language"

# Swift app without SwiftPM: a lower-case tests/ folder must not trigger `swift test` (macOS disks ignore case),
# and bash scripts (process substitution) are checked with bash -n, not sh -n
S="$WORK/swiftc"; mkdir -p "$S"
sh bin/shipcrate init "$S" --yes --name sw --type app --lang swift --repo e/sw >/dev/null
printf '#!/bin/bash\nmkdir -p build/sw.app\necho ok 2> >(cat >&2)\n' > "$S/build.sh"
( cd "$S" && git init -q && git add -A && OUT=$(CI= sh scripts/check.sh 2>&1); printf '%s' "$OUT" > "$WORK/swout" )
grep -q 'swift test' "$WORK/swout" && bad "ran swift test without Package.swift" || ok "no swift test without a SwiftPM package"
grep -q 'shell syntax (bash): build.sh *✔' "$WORK/swout" && ok "bash scripts checked with bash -n" || bad "bash script not checked with bash -n: $(grep 'build.sh' "$WORK/swout")"

# A project's own install.sh (kept by init) must never be run by the shipped tests (it once overwrote a real binary).
H="$WORK/hostile"; mkdir -p "$H"
sh bin/shipcrate init "$H" --yes --name hz --type cli --lang python --repo e/hz >/dev/null
printf '#!/bin/sh\ntouch "%s/RAN"\nmkdir -p "$HOME/.local/bin" && touch "$HOME/.local/bin/hz-overwritten"\n' "$WORK" > "$H/install.sh"
( cd "$H" && git init -q && sh tests/shipcrate/test-scripts.sh >/dev/null 2>&1 )
[ ! -e "$WORK/RAN" ] && [ ! -e "$HOME/.local/bin/hz-overwritten" ] && ok "a project's own install.sh is never run by the tests" || bad "the tests ran the project's own install.sh!"
rm -f "$HOME/.local/bin/hz-overwritten"

# The daily Stats workflow exists only while STATS_SNAPSHOTS is on (a do-nothing cron still uses Actions minutes).
SN="$WORK/stats"; mkdir -p "$SN"; sh bin/shipcrate init "$SN" --yes --name sn --type cli --lang python --repo e/sn >/dev/null
[ ! -e "$SN/.github/workflows/stats.yml" ] && ok "no Stats workflow while snapshots are off" || bad "init wrote stats.yml with snapshots off"
sed -i.bak "s/^STATS_SNAPSHOTS=.*/STATS_SNAPSHOTS='on'/" "$SN/release.conf" && rm -f "$SN/release.conf.bak"
( cd "$SN" && git init -q && sh "$OLDPWD/bin/shipcrate" sync --allow-dev --yes >/dev/null 2>&1 )
[ -f "$SN/.github/workflows/stats.yml" ] && ok "sync adds the Stats workflow when snapshots are turned on" || bad "sync didn't add stats.yml"

# webhook-test.sh: valid sample bodies, a valid Postman collection, and a full run against the demo receiver.
WH="$WORK/wh"; mkdir -p "$WH"; sh bin/shipcrate init "$WH" --yes --name wh --type cli --lang python --repo e/wh >/dev/null
okj=1; for e in release security announcement yank; do (cd "$WH" && sh scripts/webhook-test.sh --print $e) | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || okj=0; done
[ $okj = 1 ] && ok "webhook samples are valid JSON" || bad "a webhook sample isn't valid JSON"
(cd "$WH" && sh scripts/webhook-test.sh --postman c.json >/dev/null) && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["item"])==5' "$WH/c.json" 2>/dev/null && ok "Postman collection is valid" || bad "Postman collection is invalid"
if command -v node >/dev/null && command -v openssl >/dev/null; then
  PORTW=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  RELEASE_WEBHOOK_SECRET=t PORT=$PORTW node examples/notify-receiver/server.js >/dev/null 2>&1 & RP=$!
  i=0; until curl -s "http://127.0.0.1:$PORTW" >/dev/null 2>&1 || [ $i -ge 50 ]; do i=$((i+1)); sleep 0.1; done
  (cd "$WH" && RELEASE_WEBHOOK_SECRET=t sh scripts/webhook-test.sh --url "http://127.0.0.1:$PORTW" >/dev/null) && ok "webhook test passes against the demo receiver" || bad "webhook test failed against the demo receiver"
  OUTW=$(cd "$WH" && RELEASE_WEBHOOK_SECRET=wrong sh scripts/webhook-test.sh --url "http://127.0.0.1:$PORTW" --event yank 2>&1 || true)
  printf '%s' "$OUTW" | grep -q 'yank: signed (accepted) *401' && ok "webhook test catches a wrong secret" || bad "webhook test missed a wrong secret: $OUTW"
  # a receiver that accepts anything must fail the test, with a warning
  PORTL=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  python3 -I -c 'import http.server,sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self): self.rfile.read(int(self.headers.get("Content-Length",0))); self.send_response(200); self.end_headers()
http.server.HTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()' "$PORTL" & LP=$!
  sleep 0.5; OUTL=$(cd "$WH" && RELEASE_WEBHOOK_SECRET=t sh scripts/webhook-test.sh --url "http://127.0.0.1:$PORTL" --event release 2>&1); rcl=$?
  [ $rcl != 0 ] && printf '%s' "$OUTL" | grep -q 'fake a release' && ok "webhook test flags a receiver that skips the signature check" || bad "lax receiver not flagged: $OUTL"
  kill $LP 2>/dev/null; wait $LP 2>/dev/null
  OUTD=$(cd "$WH" && RELEASE_WEBHOOK_SECRET=t sh scripts/webhook-test.sh --url "http://127.0.0.1:1" --event yank 2>&1 || true)
  printf '%s' "$OUTD" | grep -q 'no answer' && ok "webhook test explains a receiver that isn't running" || bad "receiver down: $OUTD"
  kill $RP 2>/dev/null; wait $RP 2>/dev/null || true
fi

echo; [ $FAIL -eq 0 ] && echo "All init tests passed." || echo "$FAIL init test(s) failed."
exit $FAIL
