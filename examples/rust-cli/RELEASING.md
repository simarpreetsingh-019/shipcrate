# Testing and releasing hello-ship

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
   version, builds, writes `hello-ship-{target}.tar.gz.sha256`, asks, then tags, pushes, publishes the GitHub release and bumps
   the Homebrew tap `you/homebrew-hello-ship`.
4. `.github/workflows/release.yml` signs a build-provenance attestation. Check it:
   `gh attestation verify hello-ship-{target}.tar.gz --repo you/hello-ship`.

## Update checks

The app/CLI checks for updates with one anonymous GET to
`https://api.github.com/repos/you/hello-ship/releases/latest`, at most once a day. Nothing about the user or machine is sent;
there is no telemetry. Turn it off with `HELLO_SHIP_NO_UPDATE_CHECK=1`.
