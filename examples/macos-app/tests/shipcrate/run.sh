#!/bin/sh
# shipcrate's shipped tests for HelloShip: the release scripts, the installer and the update code.
# Run by scripts/check.sh on every commit, push, CI run and release. Offline: uses file:// fake releases.
set -u
cd "$(dirname "$0")/../.."
FAIL=0
run() { if sh -c "$2" >"${TMPDIR:-/tmp}/shipcrate-test.$$" 2>&1; then echo "  ✔ $1"; else echo "  ✗ $1"; sed 's/^/      /' "${TMPDIR:-/tmp}/shipcrate-test.$$" | tail -20; FAIL=$((FAIL+1)); fi; }
run "release scripts and installer" "sh tests/shipcrate/test-scripts.sh"
[ -f tests/shipcrate/test_update_check.py ] && run "Python updater" "python3 -I tests/shipcrate/test_update_check.py"
[ -f tests/shipcrate/update-check.test.js ] && run "Node updater" "node --test tests/shipcrate/update-check.test.js"
[ -f tests/shipcrate/UpdaterTests.swift ] && [ "$(uname)" = Darwin ] && run "Swift updater" \
  "d=\$(mktemp -d) && cp updater/Updater.swift \"\$d/\" && cp tests/shipcrate/UpdaterTests.swift \"\$d/main.swift\" && swiftc -o \"\$d/t\" \"\$d/Updater.swift\" \"\$d/main.swift\" && \"\$d/t\""
# The Rust updater's tests run with `cargo test` once update.rs is in src/ (they're inside the file).
[ -f updater/update.rs ] && command -v rustc >/dev/null && run "Rust updater" \
  "d=\$(mktemp -d) && rustc --edition 2021 --test -o \"\$d/t\" updater/update.rs 2>&1 && \"\$d/t\" -q"
rm -f "${TMPDIR:-/tmp}/shipcrate-test.$$"
exit $FAIL
