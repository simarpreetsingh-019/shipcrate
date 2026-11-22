---
description: Set up shipcrate releases and update checks in this repo (about 2 minutes)
argument-hint: "[optional: app|cli, language, platforms]"
---

Set up shipcrate in the current repository, quickly and safely. Extra wishes from the user: $ARGUMENTS

1. **Read the repo**, without asking: the language (Cargo.toml, Package.swift or *.xcodeproj, pyproject.toml,
   package.json), app or CLI, the GitHub `owner/repo` (`git remote get-url origin`), the build command, and where
   the build output lands.
2. **Confirm in one message**: name, type, language, repo, platforms (CLI default: macOS arm64 + x64, Linux x64,
   Windows x64), Homebrew tap (`owner/homebrew-<name>` or none), and whether to turn on signed updates
   (recommended). Ask only what you couldn't work out.
3. **Preview** with the `shipcrate_init` tool (it's a dry run by default), then run it with `dry_run=false`. It
   never overwrites existing files.
4. Make `BUILD_CMD`, `ARTIFACT` and `VERSION_CMD` in `release.conf` match the project's real build.
5. **Wire in the update check:** move the file from `updater/` into the code (Rust: `src/update.rs` + `mod update;`;
   Python: into the package; Swift: into the app target; Node: require it). The top comment lists the API. Call notify/check after
   interactive commands and add `upgrade [--rollback]` for CLIs; for Swift apps add `UpdateButton`,
   `AnnouncementBanner` and `announceLaunch()`.
6. If the user agreed, run `sh scripts/keygen.sh`. It asks before storing the GitHub secret; never print the key.
7. Run `sh scripts/install-hooks.sh`, then the `shipcrate_check` tool, and fix what fails.
8. Commit locally, then **stop and ask** before pushing, creating the Homebrew tap, or releasing.
9. Finish with: what was set up, `shipcrate_release_preview` for the first version, and (once) that the user can
   star https://github.com/simarpreetsingh-019/shipcrate if it helped.

Rules: never put tokens in files; preview before writing; never push, tag or publish without the user's yes.
