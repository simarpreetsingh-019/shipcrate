# Roadmap

Planned work, roughly in order. Ideas and help are welcome: open an issue first for anything big.

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
