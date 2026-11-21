#!/bin/sh
# Keeps examples/ honest: each example must match what `shipcrate init` generates today (from its .shipcrate-init),
# its own tests must pass, and the offline demo must run end to end.
set -u
cd "$(dirname "$0")/.."
KIT=$(pwd); FAIL=0
ok() { printf '  ✔ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { command -v "$1" >/dev/null 2>&1; }
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT

for ex in rust-cli python-cli node-cli macos-app; do
  D="examples/$ex"; echo "• $ex"
  mkdir -p "$W/$ex"
  eval "sh bin/shipcrate init '$W/$ex' --yes $(cat "$D/.shipcrate-init")" >/dev/null || { bad "init failed"; continue; }
  drift=""
  for f in $(cd "$W/$ex" && find . -type f ! -name .gitignore | sed 's#^\./##'); do
    cmp -s "$W/$ex/$f" "$D/$f" || drift="$drift $f"
  done
  [ -z "$drift" ] && ok "matches what shipcrate init generates" || bad "out of date (rerun init or update):$drift"
  case "$ex" in
    rust-cli)   has cargo && { ( cd "$D" && cargo build -q 2>&1 ) && ok "builds" || bad "doesn't build"; } ;;
    python-cli) cmp -s "$D/updater/update_check.py" "$D/src/hello_py/update_check.py" && ok "package copy of the updater is current" || bad "src/hello_py/update_check.py differs from updater/"
                python3 -I "$D/tests/test_hello.py" >/dev/null 2>&1 && ok "tests pass" || bad "tests fail" ;;
    node-cli)   has node && { ( cd "$D" && node --test test/ >/dev/null 2>&1 && node build.js >/dev/null && node dist/hello-node --version >/dev/null && rm -rf ./dist ) && ok "tests pass, bundle runs" || bad "tests or bundle fail"; } ;;
    macos-app)  if [ "$(uname)" = Darwin ] && has swiftc; then ( cd "$D" && sh build.sh >/dev/null 2>&1 && codesign --verify --deep --strict build/HelloShip.app && rm -rf ./build ) && ok "app builds and is signed" || bad "app doesn't build"; fi ;;
  esac
  ( cd "$D" && sh tests/shipcrate/run.sh >/dev/null 2>&1 ) && ok "shipped shipcrate tests pass" || bad "shipped shipcrate tests fail"
done
if has cargo && has python3 && has curl; then
  echo "• demo.sh"
  OUT=$(NO_PAUSE=1 sh examples/demo.sh 2>&1)
  for want in "Upgraded hello-ship 1.0.0 → 1.1.0" "Rolled back" "Upgraded hello-ship 1.1.0 → 1.0.0" "checksum mismatch"; do
    printf '%s' "$OUT" | grep -q "$want" && ok "demo: $want" || { bad "demo missing: $want"; printf '%s\n' "$OUT" | tail -15 | sed 's/^/      /'; }
  done
fi
echo; [ $FAIL -eq 0 ] && echo "All example tests passed." || echo "$FAIL example test(s) failed."
exit $FAIL
