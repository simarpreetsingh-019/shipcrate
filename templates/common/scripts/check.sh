#!/bin/sh
# One quality gate for {{PRODUCT}}, used by the git hooks, CI and releases (from shipcrate).
#   sh scripts/check.sh --quick     every commit: build, tests, secrets and big files in staged changes
#   sh scripts/check.sh             every push / CI: quick on all tracked files + lint + dependency audit
#   sh scripts/check.sh --release   before a release: everything + clean working tree
# Exit code is the number of failed steps. Nothing is changed. Missing optional tools are skipped with a note.
set -u
cd "$(dirname "$0")/.."
. ./release.conf
MODE="${1:-push}"; FAIL=0
step() { printf "• %-44s" "$1"; shift; OUT=$(sh -c "$*" 2>&1); if [ $? -eq 0 ]; then echo "✔"; else echo "✗"; FAIL=$((FAIL+1)); echo "$OUT" | tail -15 | sed 's/^/    /'; fi; }
skip() { printf "• %-44s– skipped: %s\n" "$1" "$2"; }
has() { command -v "$1" >/dev/null 2>&1; }

files() { if [ "$MODE" = "--quick" ]; then git diff --cached --name-only --diff-filter=ACM; else git ls-files; fi; }
scan_secrets() {
  files | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -I -n -E 'hf_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{32,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[bpas]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f" 2>/dev/null | cut -c1-120 | sed "s|^|$f:|"
  done | { HITS=$(cat); [ -z "$HITS" ] || { echo "possible secret(s):"; echo "$HITS"; exit 1; }; }
}
scan_big() {
  files | while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *.gguf|*.safetensors|*.pt|*.pth|*.ckpt|*.onnx|*.mlmodel|.env|*.p12|*.pem|*.key) echo "blocked file type: $f";; esac
    s=$(wc -c < "$f" | tr -d ' '); [ "$s" -gt 5242880 ] && echo "over 5 MB: $f ($((s / 1048576)) MB)"
  done | { OUT=$(cat); [ -z "$OUT" ] || { echo "$OUT"; exit 1; }; }
}

echo "$PRODUCT check ($MODE)"
case "$KIT_LANG" in
  rust)
    step "build"                     cargo build --quiet
    step "tests"                     cargo test --quiet ;;
  swift)
    if [ -f Package.swift ]; then step "build" swift build -q; else step "build" "$BUILD_CMD"; fi
    if [ -d Tests ]; then step "tests" swift test -q; else skip "tests" "no Tests/ folder"; fi ;;
  python)
    step "byte-compile"              python3 -m compileall -q -x '/\.venv/' .
    if [ -d tests ] && python3 -c 'import pytest' 2>/dev/null; then step "tests (pytest)" python3 -m pytest -q
    elif [ -d tests ]; then step "tests (unittest)" python3 -m unittest discover -q -s tests
    else skip "tests" "no tests/ folder"; fi ;;
  node)
    [ -d node_modules ] || step "install dependencies" npm ci --silent
    step "build"                     npm run build --if-present --silent
    step "tests"                     npm test --if-present --silent ;;
esac
printf "• %-44s" "no secrets in committed files"; if (scan_secrets); then echo "✔"; else FAIL=$((FAIL+1)); fi
printf "• %-44s" "no model/key files or files > 5 MB"; if (scan_big); then echo "✔"; else FAIL=$((FAIL+1)); fi

if [ "$MODE" != "--quick" ]; then
  for f in $(git ls-files '*.sh' .githooks 2>/dev/null); do step "shell syntax: $f" sh -n "$f"; done
  case "$KIT_LANG" in
    rust)
      step "lint (clippy correctness, suspicious)" cargo clippy --all-targets --quiet -- -D clippy::correctness -D clippy::suspicious
      if cargo audit --version >/dev/null 2>&1; then step "dependency advisories (cargo audit)" cargo audit --quiet
      else skip "dependency advisories" "cargo install cargo-audit --locked"; fi ;;
    swift)
      if has swiftlint; then step "lint (swiftlint)" swiftlint --quiet; else skip "lint" "brew install swiftlint"; fi ;;
    python)
      if has ruff; then step "lint (ruff)" ruff check -q .; else skip "lint" "pipx install ruff"; fi
      if has pip-audit; then step "dependency advisories (pip-audit)" pip-audit -q; else skip "dependency advisories" "pipx install pip-audit"; fi ;;
    node)
      step "lint"                                npm run lint --if-present --silent
      step "dependency advisories (npm audit)"   npm audit --audit-level=high --omit=dev ;;
  esac
fi
if [ "$MODE" = "--release" ]; then
  step "working tree clean" '[ -z "$(git status --porcelain)" ]'
fi
echo; [ $FAIL -eq 0 ] && echo "All checks passed." || echo "$FAIL check(s) failed."
exit $FAIL
