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

for combo in "app swift Thermo" "cli rust msh" "cli python pytool" "cli node nodetool" "cli swift swiftcli"; do
  set -- $combo; TYPE=$1; L=$2; N=$3; D="$WORK/$N"; mkdir -p "$D"
  echo "• init $N ($TYPE, $L)"
  check "init runs" sh "$KIT/bin/shipcrate" init "$D" --yes --name "$N" --type "$TYPE" --lang "$L" --repo "example/$N" --desc "Test $N"
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
  ( cd "$D" && mkdir -p dist && echo "abc  x" > "dist/$(. ./release.conf; echo "$ASSET").sha256" && printf '## [1.0.0]\n- thing\n' > CHANGELOG.md &&
    sh scripts/release-notes.sh 1.0.0 --security | grep -q '\[security\]' && sh scripts/release-notes.sh 1.0.0 | grep -q 'thing' ) \
    && ok "release notes: What's new + security marker" || bad "release notes"
done

echo "• safety"
D="$WORK/safe"; mkdir -p "$D"
sh bin/shipcrate init "$D" --dry-run --yes --name s --type cli --lang rust --repo e/s >/dev/null
[ -z "$(ls -A "$D")" ] && ok "--dry-run writes nothing" || bad "--dry-run wrote files"
echo keep > "$D/CHANGELOG.md"
sh bin/shipcrate init "$D" --yes --name s --type cli --lang rust --repo e/s >/dev/null
[ "$(cat "$D/CHANGELOG.md")" = keep ] && ok "existing files are not overwritten" || bad "overwrote an existing file"
sh bin/shipcrate init "$D" --yes --name s --type cli --lang ruby --repo e/s >/dev/null 2>&1 && bad "accepted bad --lang" || ok "rejects unknown language"

echo; [ $FAIL -eq 0 ] && echo "All init tests passed." || echo "$FAIL init test(s) failed."
exit $FAIL
