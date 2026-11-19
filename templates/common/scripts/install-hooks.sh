#!/bin/sh
# Turn on the git hooks for this clone (pre-commit: quick checks; pre-push: full checks).
cd "$(dirname "$0")/.." && chmod +x .githooks/* scripts/*.sh && git config core.hooksPath .githooks && echo "Hooks on: pre-commit and pre-push run scripts/check.sh."
