#!/bin/sh
# Tell your own systems about a release: POST dist/latest.json to a webhook (your push server, Slack relay, etc.).
# Off unless RELEASE_WEBHOOK_URL is set in the ENVIRONMENT (CI secret or your shell). Never put it in a file.
#   RELEASE_WEBHOOK_URL      https endpoint that receives the JSON
#   RELEASE_WEBHOOK_SECRET   optional: signs the body; header  X-Shipcrate-Signature: sha256=<hex HMAC-SHA256>
# Your server should verify the signature, then fan out to its push channels (APNs, FCM, email, in-app inbox…).
set -eu
cd "$(dirname "$0")/.."
URL="${RELEASE_WEBHOOK_URL:-}"
[ -n "$URL" ] || { echo "• release webhook: not configured (RELEASE_WEBHOOK_URL unset), skipped"; exit 0; }
case "$URL" in https://*) ;; *) echo "✗ RELEASE_WEBHOOK_URL must be https"; exit 1 ;; esac
[ -f dist/latest.json ] || { echo "✗ dist/latest.json missing: run scripts/manifest.sh first"; exit 1; }
set -- -fsS --max-time 20 -X POST -H "Content-Type: application/json" -H "User-Agent: shipcrate-release" --data-binary @dist/latest.json
if [ -n "${RELEASE_WEBHOOK_SECRET:-}" ]; then
  SIG=$(openssl dgst -sha256 -hmac "$RELEASE_WEBHOOK_SECRET" -r dist/latest.json | cut -d' ' -f1)
  set -- "$@" -H "X-Shipcrate-Signature: sha256=$SIG"
fi
curl "$@" "$URL" >/dev/null && echo "✓ release webhook delivered" || { echo "✗ release webhook failed (the release itself is published)"; exit 1; }
