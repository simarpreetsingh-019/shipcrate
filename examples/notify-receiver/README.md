# Demo: connect your notification service

This is a small Node server, with no dependencies, that receives shipcrate's release webhook. It checks the
signature and forwards a one-line message to Slack, Discord or your own push service.

```text
shipcrate release / announce ──POST latest.json──▶ this server ──▶ Slack · Discord · your push gateway (APNs/FCM/email)
         (signed: X-Shipcrate-Signature)              verify()            forward()
```

## Try it locally (2 minutes)

```sh
cd examples/notify-receiver
RELEASE_WEBHOOK_SECRET=dev-secret node server.js            # terminal 1

# terminal 2: pretend to be shipcrate
body='{"name":"msh","version":"0.3.0","security":false,"page":"https://example.com","assets":{"macos-arm64":{}}}'
sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac dev-secret -r | cut -d' ' -f1)
curl -X POST localhost:8787 -H "X-Shipcrate-Signature: sha256=$sig" -H "X-Shipcrate-Event: release" -d "$body"
```

Terminal 1 prints `🚀 New release: msh 0.3.0 (macos-arm64) · https://example.com`. An unsigned request gets `401`.

**Test every event at once.** In a project set up with shipcrate, this sends the real message shapes for a
release, a security release, an announcement and a yank, each signed, wrongly signed and unsigned:

```sh
RELEASE_WEBHOOK_SECRET=dev-secret shipcrate webhook test --url http://localhost:8787
```

**Watch it live:** start the receiver with `VIEW=1` and open http://localhost:8787/ : every message, accepted or
refused, with its one-line summary (served only to this machine, refreshes every 2 s).

**Postman:** import [shipcrate-webhooks.postman_collection.json](shipcrate-webhooks.postman_collection.json), set
the collection variables `url` and `secret`, and run it. A pre-request script signs each body, and the tests
check accepted (2xx) and refused (4xx). For your own project's names, generate one:
`shipcrate webhook test --postman webhooks.postman_collection.json`.

## Use it for real

1. Deploy `server.js` anywhere that runs Node 18+ (a small VM, Fly.io, Render, a container) behind **HTTPS**.
2. Set `RELEASE_WEBHOOK_SECRET` to a long random value (`openssl rand -hex 32`), plus any of `SLACK_WEBHOOK_URL`,
   `DISCORD_WEBHOOK_URL` and `FORWARD_URL`.
3. In your product's GitHub repository, go to Settings → Secrets → Actions and add `RELEASE_WEBHOOK_URL`
   (https://your-host/) and `RELEASE_WEBHOOK_SECRET` (the same value as in step 2).

Every release now notifies your channels. To send a message without a release:

```sh
sh scripts/announce.sh "Planned maintenance Sunday 02:00 UTC" --level warning --url https://status.example.com
```

The message goes into `latest.json`, so every installed app and CLI shows it once at its next daily check. Your
webhook gets it too, with `X-Shipcrate-Event: announcement`.

## Your own push service

Replace `forward()` with a call to your system: an APNs/FCM gateway, an email list, or an in-app inbox. `FORWARD_URL`
receives `{ event, name, version, security, page, announcement, text }`. Keep `verify()` as it is: it's what stops
anyone else from sending your users notifications.

Tests: `node --test examples/notify-receiver/`.
