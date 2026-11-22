#!/bin/sh
# One quality gate for {{PRODUCT}}, used by the git hooks, CI and releases (from shipcrate).
#   sh scripts/check.sh --quick     every commit: build, tests, secrets and big/key files in staged changes
#   sh scripts/check.sh             every push / CI: quick on all tracked files + lint + audit + guardrails
#   sh scripts/check.sh --release   before a release: everything, and nothing may be skipped
# In --release mode a missing tool or missing tests FAIL instead of being skipped: a release always has
# tests, a dependency audit and the security checks behind it.
# Exit code is the number of failed steps. Nothing is changed.
set -u
cd "$(dirname "$0")/.."
. ./release.conf
MODE="${1:-push}"; FAIL=0
step() { printf "• %-46s" "$1"; shift; OUT=$(sh -c "$*" 2>&1); if [ $? -eq 0 ]; then echo "✔"; else echo "✗"; FAIL=$((FAIL+1)); printf '%s\n' "$OUT" | tail -15 | sed 's/^/    /'; fi; }
skip() { if [ "$MODE" = --release ]; then printf "• %-46s✗ required for a release: %s\n" "$1" "$2"; FAIL=$((FAIL+1)); else printf "• %-46s– skipped: %s\n" "$1" "$2"; fi; }
fstep() { printf "• %-46s" "$1"; OUT=$( ($2) 2>&1); if [ $? -eq 0 ]; then echo "✔"; else echo "✗"; FAIL=$((FAIL+1)); printf '%s\n' "$OUT" | tail -15 | sed 's/^/    /'; fi; }
has() { command -v "$1" >/dev/null 2>&1; }

files() { if [ "$MODE" = "--quick" ]; then git diff --cached --name-only --diff-filter=ACM; else git ls-files; fi; }
scan_secrets() {
  files | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -I -n -E 'hf_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{32,}|sk-ant-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|ghs_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[bpas]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|npm_[A-Za-z0-9]{36}|pypi-[A-Za-z0-9_-]{50,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f" 2>/dev/null | cut -c1-120 | sed "s|^|$f:|"
  done | { HITS=$(cat); [ -z "$HITS" ] || { echo "possible secret(s):"; echo "$HITS"; exit 1; }; }
}
scan_big() {
  files | while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *.gguf|*.safetensors|*.pt|*.pth|*.ckpt|*.onnx|*.mlmodel|.env|.env.*|*.p12|*.pfx|*.pem|*.key|*.keystore|*.mobileprovision|id_rsa*|id_ed25519*) echo "blocked file type: $f";; esac
    s=$(wc -c < "$f" | tr -d ' '); [ "$s" -gt 5242880 ] && echo "over 5 MB: $f ($((s / 1048576)) MB). Videos: ffmpeg -i in.mp4 -crf 24 out.mp4; or attach big files to a GitHub release instead"
  done | { OUT=$(cat); [ -z "$OUT" ] || { printf '%s\n' "$OUT"; exit 1; }; }
}
# Guardrails for GitHub workflows: least privilege, no untrusted-code triggers, known actions only.
lint_workflows() {
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    grep -q '^permissions:' "$f" || echo "$f: add a top-level 'permissions:' block (least privilege)"
    grep -n 'pull_request_target' "$f" | sed "s|^|$f: pull_request_target runs untrusted code with secrets: |"
    grep -n 'permissions: *write-all' "$f" | sed "s|^|$f: write-all: |"
    grep -nE 'echo .*\$\{\{ *secrets\.' "$f" | sed "s|^|$f: never echo secrets: |"
    grep -nE 'run:.*\$\{\{ *github\.event\.(issue|pull_request|comment|head_commit)' "$f" | sed "s|^|$f: untrusted input in run: (use env:) |"
    grep -nE '^\s*(-\s*)?uses:' "$f" | grep -vE "uses: *(actions/|github/|\./)|@[0-9a-f]{40}" | sed "s|^|$f: third-party action not pinned to a commit SHA: |"
  done | { OUT=$(cat); [ -z "$OUT" ] || { echo "$OUT"; exit 1; }; }
}
# release.conf is committed: it must never hold a credential.
lint_conf() { ! grep -nE '(TOKEN|SECRET|PASSWORD|API_KEY|WEBHOOK_URL)=["'"'"']?[^"'"'"' ]{8,}' release.conf | grep -v '^TOKEN=' ; }

echo "$PRODUCT check ($MODE)"
case "$KIT_LANG" in
  rust)
    step "build"                     cargo build --quiet
    step "tests"                     cargo test --quiet ;;
  swift)
    if [ -f Package.swift ]; then step "build" swift build -q; else step "build" "$BUILD_CMD"; fi
    # `swift test` needs a SwiftPM package with a Tests/ folder (exact case: macOS disks ignore case, so tests/ would match -d)
    if [ -f Package.swift ] && ls -1 | grep -qx Tests; then step "tests" swift test -q
    elif [ -f tests/shipcrate/run.sh ]; then printf "• %-46s– no SwiftPM tests; shipcrate's tests run below\n" "tests"
    else skip "tests" "no SwiftPM Tests/ folder"; fi ;;
  python)
    step "byte-compile"              python3 -m compileall -q -x '/\.venv/' .
    if [ -d tests ] && python3 -c 'import pytest' 2>/dev/null; then step "tests (pytest)" python3 -m pytest -q
    elif [ -d tests ]; then step "tests (unittest)" python3 -m unittest discover -q -s tests
    else skip "tests" "no tests/ folder"; fi ;;
  node)
    [ -d node_modules ] || [ ! -f package-lock.json ] || step "install dependencies" npm ci --silent
    step "build"                     npm run build --if-present --silent
    step "tests"                     npm test --if-present --silent ;;
esac
[ -f tests/shipcrate/run.sh ] && step "shipcrate tests (installer, updater, scripts)" sh tests/shipcrate/run.sh
fstep "no secrets in committed files" scan_secrets
fstep "no key/model files or files > 5 MB" scan_big

if [ "$MODE" != "--quick" ]; then
  for f in $(git ls-files '*.sh' .githooks 2>/dev/null); do
    case "$(head -1 "$f")" in *bash*) step "shell syntax (bash): $f" bash -n "$f" ;; *) step "shell syntax: $f" sh -n "$f" ;; esac
  done
  fstep "workflow guardrails" lint_workflows
  fstep "release.conf holds no credentials" lint_conf
  if has gitleaks; then step "secret history scan (gitleaks)" gitleaks git --no-banner --redact -q .; else H="${XDG_CACHE_HOME:-$HOME/.cache}/shipcrate/hint-gitleaks"; [ -f "$H" ] || { printf "• %-46s– optional: brew install gitleaks (shown once)\n" "secret history scan"; mkdir -p "$(dirname "$H")" 2>/dev/null && touch "$H" 2>/dev/null; }; fi
  case "$KIT_LANG" in
    rust)
      step "lint (clippy correctness, suspicious)" cargo clippy --all-targets --quiet -- -D clippy::correctness -D clippy::suspicious
      if cargo audit --version >/dev/null 2>&1; then step "dependency advisories (cargo audit)" cargo audit --quiet
      else skip "dependency advisories" "cargo install cargo-audit --locked"; fi ;;
    swift)
      if has swiftlint && swiftlint version >/dev/null 2>&1; then step "lint (swiftlint)" swiftlint --quiet
      elif [ -z "${CI:-}" ]; then printf "• %-46s– skipped locally (needs swiftlint + full Xcode); runs in CI\n" "lint (swiftlint)"
      else skip "lint" "brew install swiftlint"; fi
      if [ -f Package.resolved ]; then step "dependencies pinned (Package.resolved)" true; fi ;;
    python)
      if has ruff; then step "lint (ruff)" ruff check -q .; else skip "lint" "pipx install ruff"; fi
      if has pip-audit; then step "dependency advisories (pip-audit)" pip-audit -q; else skip "dependency advisories" "pipx install pip-audit"; fi ;;
    node)
      step "lint"                                npm run lint --if-present --silent
      if [ -f package-lock.json ]; then step "dependency advisories (npm audit)" npm audit --audit-level=high --omit=dev
      else skip "dependency advisories" "commit a package-lock.json"; fi ;;
  esac
fi
if [ "$MODE" = "--release" ]; then
  step "working tree clean" '[ -z "$(git status --porcelain)" ]'
  step "SECURITY.md present" '[ -f SECURITY.md ]'
fi
echo; [ $FAIL -eq 0 ] && echo "All checks passed." || echo "$FAIL check(s) failed."
exit $FAIL
