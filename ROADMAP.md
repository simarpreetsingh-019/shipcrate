# Roadmap

Planned work, roughly in order. Ideas and help are welcome: open an issue first for anything big.

## Learned from other tools (top priority)

Ideas from GoReleaser, dist (cargo-dist), Sparkle, Velopack, the Tauri updater and release-please:

- [x] **Signed updates** (Sparkle uses EdDSA, Tauri uses minisign): sign `latest.json` and every file with an
      Ed25519 key, and embed the public key in the app/CLI, so updaters verify it themselves even if GitHub or a
      mirror were compromised. Today clients check SHA-256 from the manifest over HTTPS; provenance is checked only
      by `gh attestation verify`.
- [x] **`shipcrate` as one installable command** (GoReleaser and dist are single tools): `brew install shipcrate`,
      with `shipcrate release | check | rollout | yank | announce | status | doctor`, released with shipcrate itself.
- [x] **Timed phased rollout** (Sparkle spreads an update over 7 days): `--rollout-days 7` grows the percentage
      on the client from the publish date, with no follow-up commands.
- [x] **Minimum version / critical update** (Sparkle has critical updates): `shipcrate min-version X` (or
      `release.sh --min-version X`) makes older copies show a must-update notice at every check, ignoring rollout.
- [x] **Automatic versions and changelog** (release-please, changesets): suggest the next version and write
      the CHANGELOG section from conventional commits.
- [x] **SBOM and Sigstore/cosign signing** (GoReleaser): an SBOM per release (syft) and keyless signatures next to the provenance.
- [ ] **Built-in announcers** (GoReleaser, dist): post releases to X, Bluesky, Mastodon, Discord and Slack without
      running your own webhook server.
- [ ] **Delta updates for big apps** (Sparkle, Velopack): download only what changed.
- [ ] **Immutable releases compatibility** (GitHub immutable releases, GoReleaser v2.16): keep editable data
      (rollout, announcements, yanks) in the `channel` release, so release files are never re-uploaded.
- [ ] **Brand theming** for the update UI: Swift `UpdaterTheme` (colors, radius, icons, wording) and a CLI message
      template with an optional color that respects `NO_COLOR`.
- [ ] **Config from the project's own manifest** (dist reads `[workspace.metadata.dist]`): take name, version,
      description and targets from Cargo.toml, package.json or pyproject.toml, so release.conf only holds what
      they can't.
- [ ] **Generated workflows with a check mode** (`dist generate` / `--check`): rebuild CI and release workflows
      from config, and fail CI when they drift, instead of "your edits" merges in sync.
- [ ] **Updater as a package** (axoupdater): publish the std-only Rust updater as a crate (and the Python/Node
      ones on PyPI/npm), so projects get fixes through their package manager with no file to copy.
- [x] **`shipcrate plan`** (`dist plan`): one dry run of the whole release (files per platform, installers,
      manifest, tap) without building.
- [ ] **Say when dist is the better fit:** for a Rust CLI that only needs builds, installers and Homebrew, dist is
      the mainstream choice. Lead the docs with what shipcrate adds: signed manifests, staged and timed rollout,
      yank, announcements and beta channels.

## From real use (msh, Thermo)

- [x] No Actions minutes for nothing: the Stats workflow only exists while `STATS_SNAPSHOTS` is on; `release.sh --trust-ci` skips re-running the gate when CI passed on that commit

- [ ] `shipcrate init --diff` and a merge choice for files that already exist; `--existing` mode that proposes keep/replace/merge per file
- [ ] Gate and CI runner follow TARGETS: macOS-only projects run on macOS (doctor flags macOS-only code on ubuntu)
- [ ] Split the release gate: CI runs push mode, local release runs `--release` plus project steps that need local resources (`RELEASE_LOCAL_STEPS`)
- [ ] Non-interactive `status(current)` in the updaters for GUIs, tray apps and web UIs (latest, offered, yanked, security, announcement)
- [ ] Post-upgrade health check: optional `verify_cmd` (e.g. `<bin> --version`), automatic rollback on failure
- [ ] Docs for projects with their own updater: the `#[path]` wrapper pattern and migrating old backups to `.NAME.old`
- [ ] Templates: Homebrew `desc` from Cargo.toml/package.json/pyproject; no "in none" text when there's no tap
- [ ] install.sh: platform guard from TARGETS and a `POST_INSTALL_HINT` from release.conf
- [ ] The gate puts the freshly built binary first on PATH for steps that call the tool by name
- [ ] `init --adopt`: wrap a repo's existing release script and updater instead of adding a second copy (Thermo)
- [ ] Build presets: swiftc (no SwiftPM), SwiftPM, Xcode project, Go, Rust, Node
- [ ] `doctor` lists missing tools with install commands (gitleaks, swiftlint, gh auth, Xcode vs Command Line Tools)
- [ ] Optional notarization step, plus a guide for the "can't verify" warning on unsigned zips
- [ ] `release --dry-run` shows the release notes and the latest.json diff side by side
- [ ] Launch post templates (Reddit, HN, X, awesome lists)
- [ ] CI fixture repos on a macOS runner: a small swiftc app and a bash-heavy repo

## Next

- [ ] **Windows and Linux desktop apps.** Support GUI apps beyond the macOS `.app`: Tauri, Electron, .NET and
      Qt/GTK. That means:
  - [ ] an app type for Windows and Linux in `shipcrate init`, with packaging per platform
  - [ ] connecting each framework's own updater (Tauri updater, electron-updater…) to shipcrate's releases and `latest.json`
  - [ ] beta, rollout, yank and announcements working in those apps
  - [ ] code signing notes: Authenticode on Windows, signatures or AppImage on Linux
- [ ] **winget and Scoop** (Windows package managers):
  - [ ] generate a winget manifest and a Scoop bucket entry per release, like the Homebrew tap bump
  - [ ] `scripts/release.sh` updates them, and `yank.sh` sends them back to the good version
- [ ] **Linux packages (.deb, .rpm)**:
  - [ ] build `.deb` (Debian, Ubuntu) and `.rpm` (Fedora, RHEL, openSUSE) for CLI and desktop targets
  - [ ] checksums and provenance for each, plus installer support
  - [ ] later: an apt/dnf repository, Flatpak, Snap, AppImage
- [ ] **More languages:**
  - [ ] **Go**, first: build defaults, gate steps (`go vet`, `go test`, `govulncheck`) and an updater with tests
  - [ ] then C#/.NET, Java/Kotlin, C/C++ (CMake), Zig
- [ ] **Mobile (Android, iOS)**, to explore: the stores handle updates and signing, so this is release help
      (gate, versioning, changelog, Fastlane / Play Console / App Store Connect hand-off) rather than an updater.

## Later

- [ ] Dynamic social preview cards: one per page, rebuilt with each release, showing the version
- [ ] Minisign or Sigstore signatures for checksums, in addition to provenance
- [ ] Publish the MCP server to the MCP registries
- [ ] A `shipcrate doctor` command that checks a project's setup and explains any fixes

Done items move to [CHANGELOG.md](CHANGELOG.md).
