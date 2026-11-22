#!/bin/sh
# Started your repo from shipcrate's "Use this template" button? Run this once:   sh start.sh
# It asks what you're building (Rust, Python or Node CLI, or a SwiftUI Mac app), turns this repo into that one
# ready-to-release project named after your repo, and removes everything else that came with the template.
# Options: --kind rust-cli|python-cli|node-cli|macos-app  --name NAME  --yes
set -eu
cd "$(dirname "$0")"
ORIGIN=$(git remote get-url origin 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' || true)
case "$ORIGIN" in simarpreetsingh-019/shipcrate|"") [ "${SHIPCRATE_START_FORCE:-}" = 1 ] || {
  echo "This is shipcrate itself (or has no GitHub remote). start.sh is for repos made with \"Use this template\"."
  echo "To start a project here anyway: shipcrate new <kind> <dir>"; exit 1; } ;; esac
KIND=""; ARGS=""; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --kind) KIND="${2:?}"; shift ;; --yes|-y) YES=1; ARGS="$ARGS --yes" ;;
  --name) ARGS="$ARGS --name $(printf '%s' "${2:?}" | tr -cd 'A-Za-z0-9._ -' | tr ' ' '-')"; shift ;;
  *) echo "unknown option $1"; exit 2 ;;
esac; shift; done
if [ -z "$KIND" ]; then
  if [ $YES = 1 ] || [ ! -t 0 ]; then echo "✗ pass --kind rust-cli|python-cli|node-cli|macos-app"; exit 2; fi
  echo "What are you building?"
  echo "  1) Rust command-line tool      3) Node.js command-line tool"
  echo "  2) Python command-line tool    4) SwiftUI Mac app"
  printf 'Choose 1-4: '; read -r n
  case "$n" in 1) KIND=rust-cli ;; 2) KIND=python-cli ;; 3) KIND=node-cli ;; 4) KIND=macos-app ;; *) echo "✗ pick 1-4"; exit 2 ;; esac
fi
case "$KIND" in rust-cli|python-cli|node-cli|macos-app) ;; *) echo "✗ unknown kind $KIND"; exit 2 ;; esac

W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
sh tools/make-templates.sh "$W" --only "$KIND" >/dev/null
# Replace this repo's files with the chosen project (git history keeps the template's files if you ever want them).
git ls-files -z | xargs -0 git rm -q -f --
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$W/shipcrate-template-$KIND/." .
git add -A
echo "→ Starting a $KIND project in $ORIGIN"
sh setup.sh --repo "$ORIGIN" $ARGS
