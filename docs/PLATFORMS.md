# Platforms

| | macOS | Linux | Windows |
|---|---|---|---|
| CLI builds (`TARGETS`) | `macos-arm64`, `macos-x64` | `linux-x64`, `linux-arm64` | `windows-x64`, `windows-arm64` (.zip) |
| CI runner | `macos-latest`, `macos-15-intel` | `ubuntu-latest`, `ubuntu-24.04-arm` | `windows-latest`, `windows-11-arm` |
| Installer | `install.sh` | `install.sh` | `install.ps1` |
| Homebrew | formula (CLI), cask (app) | formula (Linuxbrew) | not supported (winget/Scoop: planned) |
| Update check + `upgrade` | ✔ | ✔ | ✔ (renames the running .exe, then swaps) |
| GUI app with in-app updater | ✔ Swift `.app` | — | — |
| Release scripts (`release.sh`, gate) | ✔ | ✔ | Git Bash (CI uses `shell: bash`) |

## Choosing targets

```sh
shipcrate init --type cli --lang rust --targets "macos-arm64 linux-x64 windows-x64" …
```

Or edit `TARGETS` in `release.conf`. With `BUILD_WHERE=ci`, a `v*` tag builds each target natively on its own
runner. Then one job checks every checksum, writes `SHA256SUMS` and `latest.json`, attests every file and publishes.
Python and Node CLIs default to `any`: one archive for every platform, which `pip`/`npm` users don't need anyway.

`BUILD_CMD` runs with `$TARGET` set. Use it if your build needs per-platform flags, or set `CROSS_OK=1` when
`BUILD_CMD` cross-compiles (for example `cargo zigbuild`).

## GUI apps on Windows and Linux

The `app` type is a macOS `.app` with a Swift updater. For Windows and Linux desktop apps, use your framework's own
updater (Tauri updater, electron-updater, Sparkle-like feeds). Point it at the same release files. The `latest.json`
manifest and the checksums still apply, and the release guardrails and gate work for any language.

## Code signing

Checksums and provenance prove where a file came from. OS signing is separate and is still needed for a
warning-free first launch:

- **macOS:** Developer ID signing and notarization (`notarytool`) in `BUILD_CMD`
- **Windows:** Authenticode (`signtool`)

Without signing, `install.sh` verifies the file and then clears macOS quarantine, as Homebrew does.
