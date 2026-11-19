#!/bin/sh
# shipcrate's own quality gate: used by its git hooks and CI.
#   sh scripts/check.sh [--quick]
set -u
cd "$(dirname "$0")/.."
MODE="${1:-push}"; FAIL=0
step() { printf "• %-44s" "$1"; shift; OUT=$(sh -c "$*" 2>&1); if [ $? -eq 0 ]; then echo "✔"; else echo "✗"; FAIL=$((FAIL+1)); echo "$OUT" | tail -25 | sed 's/^/    /'; fi; }
files() { if [ "$MODE" = "--quick" ]; then git diff --cached --name-only --diff-filter=ACM; else git ls-files; fi; }
echo "shipcrate check ($MODE)"
for f in bin/shipcrate skills/install.sh $(git ls-files '*.sh' 2>/dev/null) .githooks/*; do [ -f "$f" ] && step "sh -n $f" sh -n "$f"; done
step "no secrets in tracked files" 'files | while IFS= read -r f; do [ -f "$f" ] && grep -I -n -E "hf_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{32,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[bp]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----" "$f" | sed "s|^|$f:|"; done | { ! grep .; }'
step "no email addresses outside LICENSE" 'files | grep -v -E "^LICENSE$" | while IFS= read -r f; do [ -f "$f" ] && grep -I -n -E "[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.(com|org|net|io|dev)" "$f" | grep -v -E "noreply|users\.noreply" | sed "s|^|$f:|"; done | { ! grep .; }'
step "no files > 1 MB" 'files | while IFS= read -r f; do [ -f "$f" ] && [ "$(wc -c < "$f")" -gt 1048576 ] && echo "$f"; done | { ! grep .; }'
step "skill copies are identical" 'cmp -s skills/shipcrate/SKILL.md .agents/skills/shipcrate/SKILL.md'
[ "$MODE" = "--quick" ] || step "init: every type and language" sh tests/test-init.sh
echo; [ $FAIL -eq 0 ] && echo "All checks passed." || echo "$FAIL check(s) failed."
exit $FAIL
