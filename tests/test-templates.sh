#!/bin/sh
# The starter templates work for a brand-new user: copy each one like "Use this template", run setup.sh as
# acme/widget, and check that nothing of the example's name is left, it builds, and its tests pass.
set -u
cd "$(dirname "$0")/.."
FAIL=0; ok() { printf '  ✔ %s\n' "$1"; }; bad() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { command -v "$1" >/dev/null 2>&1; }
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
sh tools/make-templates.sh "$W/out" >/dev/null
for t in rust-cli python-cli node-cli macos-app; do
  echo "• template $t"
  D="$W/new-$t"; cp -R "$W/out/shipcrate-template-$t" "$D"
  ( cd "$D" && git init -q && git config user.email t@example.invalid && git config user.name t && git config commit.gpgsign false \
    && git remote add origin "https://github.com/acme/widget.git" && git add -A && git commit -qm "from template" --no-verify ) || { bad "git setup"; continue; }
  NAME=widget; [ $t = macos-app ] && NAME=Widget
  ( cd "$D" && sh setup.sh --yes --name "$NAME" >/dev/null 2>&1 ) && ok "setup.sh runs" || { bad "setup.sh failed"; continue; }
  [ ! -e "$D/setup.sh" ] && [ ! -e "$D/.template.conf" ] && ok "setup files removed" || bad "setup.sh left behind"
  left=$(cd "$D" && grep -rIl -i -E 'hello-?ship|hello-py|hello_py|hello-node|you/' --exclude-dir=.git --exclude-dir=target . 2>/dev/null | head -5)
  [ -z "$left" ] && ok "no example names left" || bad "example names left in: $left"
  grep -q "^REPO='acme/widget'" "$D/release.conf" && ok "release.conf points at acme/widget" || bad "release.conf repo wrong"
  ( cd "$D" && sh "$OLDPWD/bin/shipcrate" sync --allow-dev --dry-run 2>&1 ) | grep -q 'has your own edits' && bad "sync thinks setup.sh's renames are your edits" || ok "sync sees shipcrate's files as untouched after setup"
  case $t in
    rust-cli)   has cargo && { ( cd "$D" && cargo build -q 2>&1 && ./target/debug/widget --version ) | grep -q 'widget 1.0.0' && ok "builds and runs as widget" || bad "rust build/run"; } ;;
    python-cli) ( cd "$D/src" && python3 -m widget --version ) | grep -q 'widget 1.0.0' && ok "runs as widget" || bad "python run"
                python3 -I "$D/tests/test_hello.py" >/dev/null 2>&1 && ok "its tests pass" || bad "python tests" ;;
    node-cli)   has node && { ( cd "$D" && node bin/widget.js --version && node --test test/*.test.js >/dev/null 2>&1 ) | grep -q 'widget 1.0.0' && ok "runs as widget, tests pass" || bad "node run/tests"; } ;;
    macos-app)  if [ "$(uname)" = Darwin ] && has swiftc; then ( cd "$D" && sh build.sh >/dev/null 2>&1 && [ -d build/Widget.app ] && [ "$(defaults read "$PWD/build/Widget.app/Contents/Info" CFBundleIdentifier)" = com.acme.widget ] ) && ok "builds Widget.app (com.acme.widget)" || bad "mac app build"; fi ;;
  esac
  ( cd "$D" && sh tests/shipcrate/run.sh >/dev/null 2>&1 ) && ok "shipped shipcrate tests pass" || bad "shipped shipcrate tests fail"
done
# "Use this template" on the main repo, then start.sh: becomes one clean project named after the new repo
echo "• main repo template + start.sh"
T="$W/from-template"; mkdir -p "$T"
git ls-files -z | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp -p "$2" "$1/$2"' _ "$T" {}
( cd "$T" && git init -q && git config user.email t@example.invalid && git config user.name t && git config commit.gpgsign false \
  && git remote add origin https://github.com/acme/gizmo.git && git add -A && git commit -qm "Initial commit" --no-verify ) || bad "template copy"
( cd "$T" && sh start.sh --kind node-cli --yes >/dev/null 2>&1 ) && ok "start.sh runs" || bad "start.sh failed"
[ ! -e "$T/bin/shipcrate" ] && [ ! -e "$T/templates" ] && [ ! -e "$T/start.sh" ] && ok "shipcrate's own files removed" || bad "template leftovers"
( cd "$T" && node bin/gizmo.js --version ) 2>/dev/null | grep -q 'gizmo 1.0.0' && ok "runs as gizmo" || bad "gizmo doesn't run"
grep -q "^REPO='acme/gizmo'" "$T/release.conf" && ok "release.conf points at acme/gizmo" || bad "repo wrong"
grep -q "simarpreetsingh-019/shipcrate'" "$T/.github/workflows/ci.yml" 2>/dev/null && bad "kit CI leaked into the project" || ok "project has its own CI"
( cd "$T" && SHIPCRATE_START_FORCE= sh start.sh --kind node-cli --yes >/dev/null 2>&1 ) && bad "start.sh ran twice" || ok "start.sh is gone after use"
# The real shipcrate repo must refuse to turn itself into a project
sh start.sh --kind rust-cli --yes >/dev/null 2>&1 && bad "start.sh ran inside shipcrate itself!" || ok "start.sh refuses to run in shipcrate itself"

# `shipcrate new` without git metadata (like a Homebrew install of shipcrate)
echo "• shipcrate new (no git, Homebrew-like install)"
K="$W/kit"; mkdir -p "$K"; git ls-files -z | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp -p "$2" "$1/$2"' _ "$K" {}
( cd "$W" && sh "$K/bin/shipcrate" new python-cli "$W/py-new" --name tool --repo acme/tool --yes >/dev/null 2>&1 ) && ok "shipcrate new runs" || bad "shipcrate new failed"
( cd "$W/py-new/src" && python3 -m tool --version ) 2>/dev/null | grep -q 'tool 1.0.0' && ok "new project runs as tool" || bad "new project doesn't run"
sh "$K/bin/shipcrate" new python-cli "$W/py-new" --yes >/dev/null 2>&1 && bad "new overwrote a folder" || ok "new refuses a non-empty folder"

echo; [ $FAIL -eq 0 ] && echo "All template tests passed." || echo "$FAIL template test(s) failed."
exit $FAIL
