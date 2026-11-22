# Testing and releasing hello-node

Every change passes one gate before it reaches GitHub: `scripts/check.sh`. The git hooks, CI and the
release script all run it, so they can't drift apart. Settings live in `release.conf` (no secrets).

## One-time setup (per clone)

```bash
sh scripts/install-hooks.sh     # pre-commit: quick checks · pre-push: full checks
gh auth login                   # releases use the GitHub CLI; never put tokens in files
```

## What runs when

| When | Command | Checks |
|---|---|---|
| Every commit (hook) | `sh scripts/check.sh --quick` | build · tests · no secrets, key files, model files or files over 5 MB in the staged changes |
| Every push (hook) and CI | `sh scripts/check.sh` | the above for all tracked files · shell syntax · lint · dependency audit |
| Before a release | `sh scripts/check.sh --release` | the above · clean working tree |

`--no-verify` skips the hooks; CI runs the gate again, so a skipped hook is still caught.

## Releasing a version

1. Add the changes under a `## [X.Y.Z]` heading in `CHANGELOG.md` and commit.
2. Try it: `sh scripts/release.sh X.Y.Z --dry-run` (builds and prints the notes, publishes nothing).
3. Release: `sh scripts/release.sh X.Y.Z` (add `--security` for a security fix). It runs the gate, sets the
   version, builds, writes `hello-node.tar.gz.sha256`, asks, then tags, pushes, publishes the GitHub release and bumps
   the Homebrew tap `you/homebrew-hello-node`.
4. `.github/workflows/release.yml` signs a build-provenance attestation. Check it:
   `gh attestation verify hello-node.tar.gz --repo you/hello-node`.

## Updating shipcrate in a live app (6 rules)

The updater is the one part of an app that can't fix itself, so changes to it go out carefully:

1. **Sync only from shipcrate releases.** `shipcrate sync` refreshes shipcrate's own files (`scripts/`,
   `tests/shipcrate/`, `.githooks/`, `updater/`) and records `SHIPCRATE_VERSION` in `release.conf`. It refuses a
   development copy of shipcrate. Your settings, workflows, installers and your copy of the updater are never
   overwritten: it lists them for you to compare.
2. **Beta first.** If shipcrate's code or the updater changed since the last stable release, `release.sh`
   asks for a beta of that version first (`X.Y.Z-beta.1`). Only testers with the beta channel on get it.
3. **Prove the update path.** `sh scripts/update-path-test.sh X.Y.Z` downloads the last stable release, builds
   the new one locally, and lets the **old copy update itself** (checksum, signature, swap, runs), all on this
   machine. `release.sh` asks for a pass on the exact commit you release.
4. **Roll out slowly.** Those releases roll out over `SAFE_ROLLOUT_DAYS` (7 by default). `scripts/yank.sh` stays
   ready if something goes wrong.
5. **Keep the old download names.** `release.sh` refuses a release that drops a file name the last release had,
   so older updaters, installers and Homebrew keep working.
6. **Experiment elsewhere.** Try new shipcrate versions on a test project (`shipcrate new rust-cli /tmp/try`)
   or shipcrate's examples, not on the live app.

Each rule has an escape hatch for when you really mean it: `--skip-beta`, `--skip-update-test`,
`--full-rollout`, `--allow-renamed-assets`.

## Update checks

The app/CLI checks for updates with one anonymous GET to
`https://api.github.com/repos/you/hello-node/releases/latest`, at most once a day. Nothing about the user or machine is sent;
there is no telemetry. Turn it off with `HELLO_NODE_NO_UPDATE_CHECK=1`.
