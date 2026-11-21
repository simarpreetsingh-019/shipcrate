# HelloShip: a SwiftUI Mac app with shipcrate

```sh
sh build.sh && open build/HelloShip.app
```

A small window with the orange **Update** button, the announcement banner, a **Beta updates** toggle and a
**Check for Updates** button. All of it is in [`Sources/HelloShipApp.swift`](Sources/HelloShipApp.swift), with each
line marked `shipcrate`:

```swift
@ObservedObject var updater = Updater.shared
UpdateButton(updater: updater)          // shows only when an update is out; red for security fixes and yanks
AnnouncementBanner(updater: updater)    // messages from scripts/announce.sh
updater.announceLaunch()                // "What's new" after an update
Updater.channel = "beta"                // the beta channel
```

`build.sh` compiles with `swiftc`, so there's no Xcode project; use your own build in `release.conf` (`BUILD_CMD`).
For real releases, sign with your Developer ID and notarize in `build.sh` (see
[Platforms](https://simarpreetsingh-019.github.io/shipcrate/platforms/)).

Releases: `sh scripts/release.sh 1.1.0` builds on your Mac, uploads `HelloShip.zip` with its checksum, bumps the cask
(`brew install --cask you/helloship/helloship`), and the app's Update button takes it from there.
