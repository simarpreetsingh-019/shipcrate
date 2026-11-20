#!/bin/sh
# Build the website locally exactly like GitHub Pages does, and serve it at http://localhost:4000/shipcrate/
#   sh tools/preview.sh            (needs Docker; uses GitHub's own Pages image)
#   sh tools/preview.sh --build    (build only, into ./_site)
set -eu
cd "$(dirname "$0")/.."
sh tools/assemble-site.sh
rm -rf ./_site && mkdir -p _site
# GitHub's own Pages build image, run the way the Pages workflow runs it.
docker run --rm -v "$PWD:/w" -e GITHUB_WORKSPACE=/w -e INPUT_SOURCE=site -e INPUT_DESTINATION=_site/shipcrate \
  -e GITHUB_REPOSITORY=simarpreetsingh-019/shipcrate ghcr.io/actions/jekyll-build-pages:v1.0.13 2>&1 | grep -E 'error|Error|done in' | tail -5
[ -f _site/shipcrate/index.html ] || { echo "✗ build failed"; exit 1; }
echo "✓ built _site/shipcrate"
[ "${1:-}" = --build ] && exit 0
echo "→ http://localhost:4000/shipcrate/   (Ctrl-C to stop)"
cd _site && exec python3 -m http.server 4000 --bind 127.0.0.1
