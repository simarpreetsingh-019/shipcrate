# Security policy for hello-py

## Reporting a vulnerability

Please report security issues privately: on GitHub, open **Security → Report a vulnerability** at
https://github.com/you/hello-py/security/advisories/new. Don't open a public issue. You'll get a reply within a few days;
fixes ship as a release marked **Security update**, which every installed copy is told about.

## How releases are protected

| Guard | What it does |
|---|---|
| Quality gate (`scripts/check.sh`) | Runs on every commit (hook), push (hook), in CI and before every release. Release mode can't skip anything: tests, dependency audit, secret scan, workflow guardrails must all run and pass. |
| Secret scan | Blocks GitHub, OpenAI, Anthropic, Hugging Face, Slack, AWS, Google, npm, PyPI tokens and private keys; blocks `.env`, key, certificate and model files and files over 5 MB. |
| Workflow guardrails | Every workflow declares least-privilege `permissions:`; no `pull_request_target`; no secrets echoed; no untrusted event text inside `run:`; third-party actions pinned to a commit SHA. |
| Release guardrails (`scripts/release.sh`) | Releases only from the default branch, in sync with GitHub, with a passing CI run for that commit, a CHANGELOG entry, a newer version number, and a clean tree. Asks before publishing. |
| Checksums | Every file has a SHA-256 in `latest.json`, `<file>.sha256` and `SHA256SUMS`. The installers and updaters refuse anything that doesn't match. |
| Provenance | `actions/attest-build-provenance` signs each release file: `gh attestation verify <file> --repo you/hello-py`. |
| Download origin | Installers and updaters only download from `https://github.com/you/hello-py/releases/download/` unless the user explicitly points them at a mirror. HTTPS only. |
| Safe upgrade | `upgrade` verifies first, swaps atomically, keeps the previous version for `--rollback`, and never runs the downloaded file during install. |

## Update checks and privacy

The app/CLI checks for updates with **one anonymous GET** of
`https://github.com/you/hello-py/releases/latest/download/latest.json`, at most once a day, interactive use only (never in
CI, scripts or without a terminal). It sends no identifiers, no usage data, no telemetry: only a generic User-Agent.
GitHub sees the request's IP address, as with any download. Turn it off with `HELLO_PY_NO_UPDATE_CHECK=1`.

## Secrets

- No tokens, passwords or keys in the repository, ever, including `release.conf`. Local releases use `gh auth login`;
  CI uses the short-lived `GITHUB_TOKEN`.
- Optional webhook settings (`RELEASE_WEBHOOK_URL`, `RELEASE_WEBHOOK_SECRET`) live in repository secrets or your shell.
  The webhook body is signed (`X-Shipcrate-Signature: sha256=<HMAC>`); receivers must verify it and use HTTPS.
- If a secret is ever committed: revoke it first, then remove it from history. Rotating is what makes you safe.

## Checklist for a security release

1. Fix on a private fork or a GitHub security advisory's temporary fork.
2. Add the fix to `CHANGELOG.md` without exploit details.
3. `sh scripts/release.sh X.Y.Z --security`: the notes and manifest are marked, users get the stronger notice.
4. Publish the advisory with the fixed version once the release is out.
