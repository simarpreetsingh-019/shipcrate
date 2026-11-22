---
description: Prepare a shipcrate release (changelog, preview), then publish only after you approve
argument-hint: "[version | auto] [--security] [--rollout N | --rollout-days D]"
---

Release this project with shipcrate. Requested: $ARGUMENTS (default: `auto`, the version suggested by the commits).

1. Run `sh scripts/changelog.sh` and show the suggested version and section. With the user's OK, add it with
   `--write` and commit.
2. Run the `shipcrate_release_preview` tool (guardrails, gate, build, notes) and show the result. Fix any guardrail
   it reports; never bypass or weaken one.
3. Show the user exactly what will happen (version, platforms, rollout, Homebrew, webhook), and **wait for a clear
   yes**.
4. Only then run `sh scripts/release.sh <version> --yes [flags]` and report the release URL and the
   `gh attestation verify` command.
