#!/bin/sh
# Assemble the website source into ./site: docs/ + llms.txt + SECURITY.md and CONTRIBUTING.md as site pages.
# Used by .github/workflows/pages.yml and tools/preview.sh, so the preview matches what GitHub builds.
set -eu
cd "$(dirname "$0")/.."
rm -rf ./site && mkdir -p site && cp -R docs/. site/ && cp llms.txt site/llms.txt
# Give docs pages front matter in the copy (not the source), so Jekyll renders them once instead of also
# publishing the raw .md (duplicate content for search engines).
for f in site/*.md; do case "$(head -1 "$f")" in ---) ;; *) { printf -- '---\n---\n'; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f" ;; esac; done
B=https://github.com/simarpreetsingh-019/shipcrate/blob/main
for f in SECURITY CONTRIBUTING; do
  out="site/$(echo "$f" | tr 'A-Z' 'a-z')-page.md"   # GitHub's Jekyll ignores files named CONTRIBUTING*
  # front matter so Jekyll renders it; raw keeps {{…}} text literal
  printf -- '---\n---\n{%% raw %%}\n' > "$out"
  sed -e "s#](docs/PLATFORMS.md)#](../platforms/)#g; s#](docs/INTEGRATING.md)#](../integrating/)#g" \
      -e "s#](templates/#]($B/templates/#g; s#](LICENSE)#]($B/LICENSE)#g; s#](tests/#]($B/tests/#g" "$f.md" >> "$out"
  printf '\n{%% endraw %%}\n' >> "$out"
done
# llms-full.txt: every doc in one plain-text file for LLMs and AI answer engines
{
  cat llms.txt
  for f in docs/quickstart.md docs/INTEGRATING.md docs/PLATFORMS.md docs/agents.md SECURITY.md CONTRIBUTING.md; do
    printf '\n\n---\n\n<!-- source: %s -->\n\n' "$f"; cat "$f"
  done
} > site/llms-full.txt
echo "✓ site/ assembled"
