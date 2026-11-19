#!/bin/sh
# Install the shipcrate skill for Claude Code (~/.claude/skills/shipcrate) and Codex (~/.codex/skills/shipcrate).
# Asks before each copy; pass --yes to skip the questions.
set -eu
SRC="$(cd "$(dirname "$0")" && pwd)/shipcrate"
YES=0; [ "${1:-}" = "--yes" ] && YES=1
for dest in "$HOME/.claude/skills/shipcrate" "$HOME/.codex/skills/shipcrate"; do
  if [ $YES = 0 ]; then
    printf 'Install the skill to %s%s? [y/N] ' "$dest" "$([ -e "$dest" ] && echo ' (replaces the existing copy)')"
    read -r ok; case "$ok" in y|Y|yes) ;; *) echo "  skipped"; continue ;; esac
  fi
  mkdir -p "$dest" && cp "$SRC/SKILL.md" "$dest/SKILL.md" && echo "  ✓ $dest/SKILL.md"
done
echo "Cursor: copy .cursor/rules/shipcrate.mdc into your project. Others: AGENTS.md."
