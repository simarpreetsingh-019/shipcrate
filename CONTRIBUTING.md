# Contributing to shipcrate

Thanks for helping! shipcrate is small on purpose: POSIX shell, no dependencies, and a security-first release flow.
Please keep changes in that spirit.

## Ways to help

- **Report a bug or ask for a feature:** [open an issue](https://github.com/simarpreetsingh-019/shipcrate/issues/new).
  Include your OS, the `shipcrate init` flags you used and the failing output.
- **Security issue:** use a [private advisory](https://github.com/simarpreetsingh-019/shipcrate/security/advisories/new). Never open a public issue for one.
- **Pull request:** fixes, new languages, new platforms, docs. For anything big, open an issue first so we can agree on the shape.

## Set up

```sh
git clone https://github.com/simarpreetsingh-019/shipcrate && cd shipcrate
sh scripts/install-hooks.sh     # pre-commit: quick gate · pre-push: full gate
sh scripts/check.sh             # shell syntax, secret scan, workflow guardrails, init + shipped tests
```

Before pushing, also run the Linux CI job on your machine: `sh tools/ci-local.sh` (Docker). It catches GNU and
mawk differences a Mac-only check misses. Windows-only code paths still need CI.

The full gate needs `ruby` (YAML and Homebrew syntax). It also uses `rustc`, `swiftc`, `node`, `python3` and `pwsh`
where they're installed; checks for a missing tool are skipped locally, and CI runs them all on macOS, Linux and Windows.

## Where things live

| Path | What |
|---|---|
| `bin/shipcrate` | The `init` command: questions, defaults per language and target, placeholder filling, safe copying |
| `templates/common/` | Copied into every project (scripts, workflows, tests, SECURITY.md…) |
| `templates/app/`, `templates/cli/` | Homebrew cask / formula, Windows installer |
| `templates/updaters/` | Update-check code per language, plus their tests in `updaters/tests/` |
| `skills/`, `.agents/`, `AGENTS.md`, `.cursor/` | Instructions for AI agents (keep the two `SKILL.md` copies identical: the gate checks) |
| `tests/test-init.sh` | Generates every project type and runs the tests shipped into each one |

Templates use `{{PLACEHOLDER}}` names filled in by `bin/shipcrate`. A leftover placeholder fails the tests.

## Rules for changes

1. **Tests come with the change.** A new language, platform or updater feature needs a test in `tests/test-init.sh`
   and, if users get the code, a shipped test in `templates/common/tests/shipcrate/` or `templates/updaters/tests/`.
2. **Never weaken a guardrail** (release-mode gate, release checks, workflow lint, checksum or host checks) without
   discussing it in an issue first.
3. **No new dependencies** for `init` or the scripts. POSIX `sh`; it must work in macOS `/bin/sh`, Linux `dash` and Git Bash.
4. **No telemetry, no secrets.** The update check stays one anonymous GET. No tokens in any file.
5. **Keep docs in step:** README, `docs/`, `SECURITY.md`, the skill and `CHANGELOG.md` (under `## [Unreleased]`).

## Adding a language (example)

1. `bin/shipcrate`: defaults in the `case "$KLANG"` block (`TARGETS`, `ASSET`, `BUILD_CMD`, `ARTIFACT`, `VERSION_CMD`).
2. `templates/common/scripts/check.sh`: build/test/lint/audit steps (in release mode, missing tools must fail).
3. `templates/common/scripts/ci-tools.sh`: install those tools on CI.
4. `templates/updaters/<lang>/` plus a test in `templates/updaters/tests/` covering host, checksum, upgrade and rollback.
5. Add the combination to `tests/test-init.sh`.

## Pull requests

- One topic per PR, with a clear description of what changed and how you tested it.
- `sh scripts/check.sh` passes locally and CI is green on all three OSes.
- By contributing you agree your work is released under the [MIT License](LICENSE).

Maintainer: [Simarpreet Singh](https://simarpreetsingh-019.github.io) · [@simarpreet_019](https://x.com/simarpreet_019)
