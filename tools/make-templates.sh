#!/bin/sh
# Build the "Use this template" starter repos from examples/ into OUT (default ./_templates):
#   sh tools/make-templates.sh [OUT]
# Each one is an example project + setup.sh (rename to your app in one command) + a template README.
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-_templates}"; mkdir -p "$OUT"
make() { # make <example> <OLD_NAME> <OLD_TOKEN> <OLD_ENV> <OLD_CLASS> <OLD_MODULE> <OLD_REPO> <OLD_TAP> <OLD_BUNDLE> <kind> <first-run>
  ex=$1; D="$OUT/shipcrate-template-$ex"; rm -rf "${D:?}"; mkdir -p "$D"
  git ls-files "examples/$ex" | while IFS= read -r f; do r=${f#examples/$ex/}; mkdir -p "$D/$(dirname "$r")"; cp -p "$f" "$D/$r"; done
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

1. Click **Use this template** (top right), create your repository, and clone it.
2. In the clone, run:
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
