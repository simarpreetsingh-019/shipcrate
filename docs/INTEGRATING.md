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

## latest.json format (schema 1)

```json
{
  "schema": 1, "name": "msh", "version": "0.3.0", "tag": "v0.3.0",
  "published": "2026-11-20T10:00:00Z", "security": false,
  "page": "https://github.com/OWNER/REPO/releases/tag/v0.3.0",
  "notes": "## What's new\n…",
  "announcement": { "id": "20261120T090000Z", "level": "info", "message": "…", "url": "https://…", "below": "" },
  "assets": {
    "macos-arm64": { "name": "msh-macos-arm64.tar.gz", "url": "https://github.com/…", "sha256": "…" },
    "linux-x64":   { "name": "msh-linux-x64.tar.gz",   "url": "https://github.com/…", "sha256": "…" }
  }
}
```

The asset keys are targets: `macos-arm64`, `macos-x64`, `linux-x64`, `linux-arm64`, `windows-x64`, `windows-arm64`, plus
`macos` (an app) or `any` (one platform-independent build). Clients look for `<os>-<arch>` first, then `<os>`, then `any`.
