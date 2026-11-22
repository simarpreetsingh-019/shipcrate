#!/bin/sh
# Build the "Use this template" starter repos from examples/ into OUT (default ./_templates):
#   sh tools/make-templates.sh [OUT] [--only KIND]      (KIND: rust-cli | python-cli | node-cli | macos-app)
# Each one is an example project + setup.sh (rename to your app in one command) + a template README.
# Used by `shipcrate new` and the main repo's start.sh. Works without git (e.g. a Homebrew install).
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-_templates}"; ONLY="${3:-}"; [ "${2:-}" = --only ] || ONLY=""; mkdir -p "$OUT"
# Project files of an example: tracked files when this is a git checkout, else everything but build output.
files_of() {
  if git rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git ls-files "examples/$1" | head -1)" ]; then git ls-files "examples/$1"
  else find "examples/$1" -type f ! -path '*/target/*' ! -path '*/dist/*' ! -path '*/build/*' ! -path '*/node_modules/*' ! -path '*/__pycache__/*' ! -name '.DS_Store'; fi
}
make() { # make <example> <OLD_NAME> <OLD_TOKEN> <OLD_ENV> <OLD_CLASS> <OLD_MODULE> <OLD_REPO> <OLD_TAP> <OLD_BUNDLE> <kind> <first-run>
  ex=$1; [ -z "$ONLY" ] || [ "$ONLY" = "$ex" ] || return 0
  D="$OUT/shipcrate-template-$ex"; rm -rf "${D:?}"; mkdir -p "$D"
  files_of "$ex" | while IFS= read -r f; do r=${f#examples/$ex/}; mkdir -p "$D/$(dirname "$r")"; cp -p "$f" "$D/$r"; done
  rm -f "$D/.shipcrate-init"
  cat > "$D/.template.conf" <<CONF
OLD_NAME='$2'
OLD_TOKEN='$3'
OLD_ENV='$4'
OLD_CLASS='$5'
OLD_MODULE='$6'
OLD_REPO='$7'
OLD_TAP='$8'
OLD_BUNDLE='$9'
FIRST_RUN='${11}'
CONF
  sed "s/{{OLD_NAME}}/$2/" templates/starter/setup.sh > "$D/setup.sh"; chmod 755 "$D/setup.sh"
  { cat <<README
# shipcrate starter: ${10}

A ready-to-release ${10}, set up with [shipcrate](https://github.com/simarpreetsingh-019/shipcrate): quality gate,
GitHub releases with checksums, provenance and signed updates, Homebrew, installers, beta, staged rollout,
rollback, and update checks that are already wired in.

## Make it yours in under 5 minutes

1. Get the project: \`shipcrate new <kind> <dir>\`, or GitHub's **Use this template** on shipcrate followed by
   \`sh start.sh\`, or copy this folder.
2. In it, run (\`shipcrate new\` and \`start.sh\` already did this):
   \`\`\`sh
   sh setup.sh
   \`\`\`
   It renames everything to your project, reads your GitHub repo from git, turns on the hooks, and offers signed
   updates.
3. Push. CI runs the gate. Then release:
   \`\`\`sh
   sh scripts/release.sh 0.1.0 --dry-run
   sh scripts/release.sh 0.1.0
   \`\`\`

With an AI agent (Claude Code): \`/plugin install shipcrate --marketplace simarpreetsingh-019/shipcrate\`, then
\`/shipcrate:setup\`. That's about 2 minutes.

---

README
    sed -e '/\.\.\/demo\.sh/d' -e 's#shipcrate init \. \$(cat \.shipcrate-init)#shipcrate init .#' "examples/$ex/README.md"; } > "$D/README.md"
  echo "✓ $D"
}
make rust-cli   hello-ship hello-ship HELLO_SHIP HelloShip hello_ship you/hello-ship you/homebrew-hello-ship "" "Rust command-line tool" "cargo run -- Ada"
make python-cli hello-py   hello-py   HELLO_PY   HelloPy   hello_py   you/hello-py   you/homebrew-hello-py   "" "Python command-line tool" "cd src && python3 -m <module> Ada   (your module is in src/)"
make node-cli   hello-node hello-node HELLO_NODE HelloNode hello_node you/hello-node you/homebrew-hello-node "" "Node.js command-line tool" "node bin/*.js Ada"
make macos-app  HelloShip  helloship  HELLOSHIP  HelloShip helloship  you/HelloShip  you/homebrew-helloship com.example.helloship "SwiftUI Mac app" "sh build.sh && open build/*.app"
