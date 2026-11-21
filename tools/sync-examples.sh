#!/bin/sh
# Refresh the shipcrate-generated files inside examples/ after templates change (keeps .gitignore and app code).
set -eu
cd "$(dirname "$0")/.."
W=$(mktemp -d); trap 'rm -rf "${W:?}"' EXIT
for d in examples/*/.shipcrate-init; do
  ex=$(dirname "$d"); mkdir -p "$W/$(basename "$ex")"
  eval "sh bin/shipcrate init '$W/$(basename "$ex")' --yes $(cat "$d")" >/dev/null
  (cd "$W/$(basename "$ex")" && find . -type f ! -name .gitignore) | while read -r f; do
    mkdir -p "$ex/$(dirname "$f")"; cp -p "$W/$(basename "$ex")/$f" "$ex/$f"
  done
  [ -f "$ex/src/hello_py/update_check.py" ] && cp "$ex/updater/update_check.py" "$ex/src/hello_py/update_check.py"
  echo "✓ $ex"
done
