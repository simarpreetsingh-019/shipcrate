# Security

## Reporting

Report vulnerabilities in shipcrate privately at
https://github.com/simarpreetsingh-019/shipcrate/security/advisories/new. Please don't open a public issue.

## What shipcrate guarantees

For every project it sets up, shipcrate also installs [templates/common/SECURITY.md](templates/common/SECURITY.md),
which explains the protections listed below to that project's users.

1. **Nothing ships without the gate.** `scripts/check.sh --release` runs before every release, both locally and in the
   release workflow. In release mode a missing test suite or audit tool counts as a failure, not a skip.
2. **Release guardrails.** Releases go out only from the default branch, in sync with the remote, after a passing CI
   run for that exact commit, with a CHANGELOG entry and a newer version number. Every release needs your approval
   unless you pass `--yes`.
3. **Signed updates** (`shipcrate keygen`). `latest.json` is signed with Ed25519, and every updater verifies it
   against the public key built into the app before trusting a version or a checksum.
4. **Supply chain.** Each release gets an SBOM (SPDX) with an SBOM attestation, and keyless Sigstore signatures
   for its files (`cosign verify-blob …`), alongside the build-provenance attestation.
5. **Verified downloads.** SHA-256 for every file (`latest.json`, `*.sha256`, `SHA256SUMS`), a build-provenance
   attestation for every file, and HTTPS only. Downloads must come from the project's own GitHub releases unless the
   user deliberately chooses a mirror.
6. **Safe upgrades.** The download is verified before anything changes. The swap is atomic, the previous version is
   kept for rollback, and archives that contain symlinks or path tricks are refused.
7. **Least-privilege workflows.** Every workflow sets explicit `permissions`. Write and attestation permissions go only
   to the publish job. No `pull_request_target`. The gate fails any workflow that echoes secrets, puts untrusted event
   text in `run:`, or uses a third-party action that isn't pinned to a commit.
8. **No secrets in files.** The gate scans for common token formats and blocks key, certificate, `.env` and model
   files. Local releases use `gh auth login`; CI uses `GITHUB_TOKEN`; webhook settings are repository secrets.
9. **Rollouts and yanks stay private.** The rollout bucket is a random number kept on the user's machine. Yanks
   and announcements change only text in `latest.json`: clients still verify every download, and they never run
   anything because of a message.
10. **Agents can't publish by themselves.** The MCP server has no publishing tools. Every agent file (skill,
   AGENTS.md, llms.txt, Cursor rule, MCP instructions) tells the agent to ask before pushing, publishing, yanking,
   changing a rollout or sending an announcement.
11. **No telemetry.** The update check is one anonymous GET of `latest.json`, at most daily, interactive use only, with
   an opt-out env var. `shipcrate init` itself makes no network requests.

## Tests that guard this

- `tests/shipcrate/` is copied into every project and runs in its gate on every commit, push, CI run and release. It
  checks that:
  - a good release installs and a tampered one is refused
  - downloads from other hosts, bad checksums and `file://` URLs are refused
  - upgrade and rollback work
  - no update checks run in CI or when opted out
- `tests/test-init.sh` (shipcrate's own CI, on macOS and Linux) generates every project type and runs those shipped tests.

## Known limits

- HMAC signing passes the webhook secret to `openssl` as an argument, so other local users can briefly see it in
  `ps`. Use CI secrets on GitHub's single-tenant runners, or a dedicated machine.
- SHA-256 proves a file matches the release. The attestation proves which repository built it. Neither replaces OS
  code signing (see [docs/PLATFORMS.md](docs/PLATFORMS.md)).
- A user who sets a custom manifest URL is trusting that server for both the file and its checksum.
