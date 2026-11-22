# Integrating shipcrate into an existing project

## Already have a release process?

Run `shipcrate init --dry-run` first: it lists what it would write and never overwrites without asking.
Take only the parts you want. They're independent:

| Want | Take |
|---|---|
| Just the safety net | `scripts/check.sh`, `.githooks/`, `scripts/install-hooks.sh`, `.github/workflows/ci.yml`, `tests/shipcrate/` |
| Checksums + provenance on your existing releases | `scripts/manifest.sh` and the `attest-upload` job in `release.yml` (it attests whatever you publish) |
| Update checks only | `updater/<your language>` plus a `latest.json` in each release (`scripts/manifest.sh` writes it) |

All settings live in `release.conf`. Point `BUILD_CMD`, `ARTIFACT` and `VERSION_CMD` at your existing build.

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

## Already have a notification system?

shipcrate doesn't replace it. There are three places to connect it, so use whichever fits.

### 1. Your app shows the notice (client side)

The updaters find the update. Your code decides how to show it.

- **Swift:** `Updater.shared.onUpdateAvailable = { release in MyNotifications.post(release) }`.
  The built-in `UpdateButton` is optional: leave it out of your UI if you don't want it.
- **Rust:** `if let Some(l) = update::check(VERSION) { my_notify(&l.version, l.security, &l.page) }`
- **Python:** `if (l := update_check.check(__version__)): my_notify(l)`
- **Node:** `const l = await update.check(version); if (l) myNotify(l);`

`check()` keeps the same rules as the built-in notice: at most once a day, interactive use only, the opt-out env
var. `l.security` tells you to make the notice louder.

### 2. Your servers push it (server side)

Each release can POST its `latest.json` to your push service, which then sends to APNs, FCM, email or an in-app inbox.

1. Add repository secrets `RELEASE_WEBHOOK_URL` (https) and, recommended, `RELEASE_WEBHOOK_SECRET`.
2. The release workflow (or `release.sh` for local builds) calls `scripts/notify.sh` after publishing.
3. Your endpoint checks `X-Shipcrate-Signature: sha256=<hex HMAC-SHA256 of the raw body>`, using a
   constant-time compare, then fans out to your channels.

Example check in Python:

```python
import hmac, hashlib
ok = hmac.compare_digest(request.headers["X-Shipcrate-Signature"],
                         "sha256=" + hmac.new(SECRET, request.body, hashlib.sha256).hexdigest())
```

A failed webhook never undoes a release. It prints a warning, and you can re-send it with `sh scripts/notify.sh`.

**Working demo:** [examples/notify-receiver](https://github.com/simarpreetsingh-019/shipcrate/tree/main/examples/notify-receiver)
is a small Node server with no dependencies that verifies the signature and forwards each release to Slack,
Discord or your own push gateway. Run it locally in two minutes, then deploy it behind HTTPS.

### 3. Your servers poll

`https://github.com/OWNER/REPO/releases/latest/download/latest.json` always points at the newest release. Poll it
from a cron job, or mirror it to your CDN and point clients there:

- CLI: `<NAME>_UPDATE_MANIFEST=https://updates.example.com/latest.json`
- Swift: `Updater.manifestURL = …` and add the host to `Updater.allowedHosts`
- Installer: `MANIFEST_URL=… sh install.sh`

Clients still check every download against the manifest's SHA-256. Only HTTPS is accepted.

## Send a message to every user (no release needed)

```sh
sh scripts/announce.sh "Planned maintenance Sunday 02:00 UTC" --level warning --url https://status.example.com
sh scripts/announce.sh "Please update: 1.x stops syncing in March" --below 2.0.0
sh scripts/announce.sh --clear
```

The message goes into the newest release's `latest.json`, after you confirm. Every installed app and CLI shows it
**once**, at its next daily check:

- CLIs print one line: `ℹ️`, `⚠️ NOTICE` or `⚠️ SECURITY NOTICE`.
- Swift apps show `AnnouncementBanner`, or call your `onAnnouncement`.
- Your webhook receives it with `X-Shipcrate-Event: announcement`, so your push servers can send it out right away.

`--below 2.0.0` limits it to versions older than 2.0.0. Announcements are text only: clients strip control
characters, keep only `https` links, and never download or run anything because of a message. A new release clears
the current announcement.

## Beta first, then everyone

**Beta channel.** Release a pre-release version: `sh scripts/release.sh 1.4.0-beta.1`. It's published as a GitHub
pre-release and to the beta manifest (`releases/download/channel/beta.json`). Stable users and Homebrew don't see it.
Users opt in with:

- CLI: `<NAME>_CHANNEL=beta`
- Swift app: `Updater.channel = "beta"` (put a toggle in your settings)

Beta users also get every stable release, so they're never left behind.

**Staged rollout.** Release to a slice of users, watch, then widen:

```sh
sh scripts/release.sh 1.4.0 --rollout 10   # 10% of installed copies see the update notice
sh scripts/rollout.sh 50
sh scripts/rollout.sh 100                  # everyone; Homebrew is bumped now
```

Each copy picks a random number from 0 to 99 once and keeps it on the user's machine. A copy gets the notice when its
number is below the percentage. Nothing is sent or tracked. Security releases (`--security`) ignore the percentage,
and a user who runs `upgrade` themselves always gets the newest version.

**Timed rollout.** `shipcrate release 1.4.0 --rollout-days 7` (or `shipcrate rollout 0 --days 7`) grows the share
from 0% to 100% over seven days, on each client, from the publish date. You don't run any follow-up commands, and
`shipcrate rollout 100` ends it early.

## Signed updates

`shipcrate keygen` turns them on: every `latest.json` gets a `latest.json.sig` (Ed25519). The Swift, Rust, Python
and Node updaters check it with the built-in public key before trusting any version or checksum, so even someone
who could change files on GitHub or your mirror can't push an update. Verification uses no extra dependencies
(CryptoKit, Node crypto, and small RFC 8032 verifiers in Rust and Python), and it costs nothing.

Keep the private key safe (a password manager is fine). It lives in `~/.config/shipcrate/` and the
`SHIPCRATE_SIGNING_KEY` repository secret, never in the repository.

## Version and changelog from commits

`shipcrate changelog` reads your commits since the last release and suggests the next version: `feat:` gives a
minor, `fix:` a patch, and `feat!:` or `BREAKING CHANGE:` a major (a minor before 1.0). It groups them under
Added, Fixed, Changed and Security. `--write` adds the section to CHANGELOG.md, and `shipcrate release auto`
uses the suggested version.

## How many people downloaded it?

```sh
shipcrate stats
```

This shows each release's downloads per platform, beta vs stable, and update checks. There's no tracking and
nothing in your app: shipcrate reads the counts GitHub keeps for every release file.

- **Archive downloads** (e.g. `mytool-macos-arm64.tar.gz` of 1.4.0) = installs and upgrades of that version.
- **`latest.json` / `beta.json` downloads** = update checks. Each copy checks at most once a day, so the daily
  growth is roughly the number of copies in use (stable vs beta).
- Counts are running totals, and they restart when a manifest is re-uploaded (by announce, rollout or yank).
  Set `STATS_SNAPSHOTS='on'` in `release.conf` and the daily Stats workflow saves them to a `stats` branch; then
  `shipcrate stats --history stats.csv` shows growth per day, e.g. how fast a rollout is being picked up.
- Not counted: unique people (two Macs count as two), Homebrew taps, and your own mirrors (use their logs).

**Leave out your own downloads.** GitHub only keeps one number per file, so it can't separate your downloads from
anyone else's. Instead, set a zero point:

```sh
shipcrate stats --baseline          # today's counts are treated as yours; from now on only newer downloads show
shipcrate stats --baseline-clear    # back to full totals
```

The zero point is saved on your machine (`~/.config/shipcrate/stats/`), and GitHub isn't changed. Run `--baseline`
again after your own testing to move it. Better still, don't count yourself in the first place: test updates
against a local manifest (`shipcrate demo`, or `<NAME>_UPDATE_MANIFEST=http://127.0.0.1:8000/latest.json`)
instead of GitHub.

Any repository works, even one not set up with shipcrate: `shipcrate stats --repo owner/name`.

## Rolling back a bad release

| Who | Command | What happens |
|---|---|---|
| One user | `mytool upgrade --rollback` | Swaps back the previous binary the upgrade kept |
| You, for everyone | `sh scripts/yank.sh 1.4.0 [--to 1.3.2] [--reason "…"]` | See below |
| You, fixing forward | `sh scripts/release.sh 1.4.1` | The normal path once you have a fix |

`yank.sh`, after you confirm:

1. Marks `v1.4.0` as **[YANKED]** with a warning at the top of its notes.
2. Makes `v1.3.2` "latest" again, with `"yanked": ["1.4.0"]` in its `latest.json`.
3. Copies on 1.4.0 are told the version was pulled. `upgrade` moves them to 1.3.2 as a normal verified install,
   checksum included.
4. Sends Homebrew and the beta channel back to 1.3.2, and calls your webhook with `X-Shipcrate-Event: yank`.

Nothing is deleted: the 1.4.0 files stay downloadable, and the git tag stays where it is.

## latest.json format (schema 1)

```json
{
  "schema": 1, "name": "msh", "version": "0.3.0", "tag": "v0.3.0",
  "published": "2026-11-20T10:00:00Z", "security": false,
  "page": "https://github.com/OWNER/REPO/releases/tag/v0.3.0",
  "notes": "## What's new\n…",
  "announcement": { "id": "20261120T090000Z", "level": "info", "message": "…", "url": "https://…", "below": "" },
  "rollout": 25,
  "yanked": ["0.2.9"],
  "assets": {
    "macos-arm64": { "name": "msh-macos-arm64.tar.gz", "url": "https://github.com/…", "sha256": "…" },
    "linux-x64":   { "name": "msh-linux-x64.tar.gz",   "url": "https://github.com/…", "sha256": "…" }
  }
}
```

The asset keys are targets: `macos-arm64`, `macos-x64`, `linux-x64`, `linux-arm64`, `windows-x64`, `windows-arm64`, plus
`macos` (an app) or `any` (one platform-independent build). Clients look for `<os>-<arch>` first, then `<os>`, then `any`.
