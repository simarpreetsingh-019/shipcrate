#!/bin/sh
# Sign a file with the project's Ed25519 key: writes FILE.sig (base64 of the 64-byte signature).
#   sh scripts/sign.sh dist/latest.json
# The private key comes from (first found): $SHIPCRATE_SIGNING_KEY (the PEM text; a CI secret),
# $SHIPCRATE_SIGNING_KEY_FILE, or ~/.config/shipcrate/<owner>-<repo>.ed25519.pem (made by scripts/keygen.sh).
# Uses OpenSSL 3 if present, else Node 18+. Does nothing when signed updates are off (no PUBLIC_KEY).
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
F="${1:?usage: sign.sh <file>}"
[ -n "${PUBLIC_KEY:-}" ] || exit 0
KEYFILE="${SHIPCRATE_SIGNING_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/shipcrate/$(printf '%s' "$REPO" | tr '/' '-').ed25519.pem}"
TMPK=""
if [ -n "${SHIPCRATE_SIGNING_KEY:-}" ]; then
  TMPK=$(mktemp); trap 'rm -f "${TMPK:?}"' EXIT; chmod 600 "$TMPK"; printf '%s\n' "$SHIPCRATE_SIGNING_KEY" > "$TMPK"; KEYFILE="$TMPK"
fi
[ -f "$KEYFILE" ] || { echo "✗ signed updates are on (PUBLIC_KEY in release.conf) but there's no signing key: set the SHIPCRATE_SIGNING_KEY secret in CI, or put the key at $KEYFILE" >&2; exit 1; }
if openssl version 2>/dev/null | grep -q '^OpenSSL [3-9]'; then
  openssl pkeyutl -sign -inkey "$KEYFILE" -rawin -in "$F" | openssl base64 -A > "$F.sig"
elif command -v node >/dev/null 2>&1; then
  node -e 'const c=require("crypto"),fs=require("fs");const k=c.createPrivateKey(fs.readFileSync(process.argv[1]));process.stdout.write(c.sign(null,fs.readFileSync(process.argv[2]),k).toString("base64"))' "$KEYFILE" "$F" > "$F.sig"
else
  echo "✗ signing needs OpenSSL 3 (brew install openssl@3) or Node 18+" >&2; exit 1
fi
# Check our own signature against the public key before anything is published.
node_check() { node -e 'const c=require("crypto"),fs=require("fs");const raw=Buffer.from(process.argv[1],"base64");const k=c.createPublicKey({key:Buffer.concat([Buffer.from("302a300506032b6570032100","hex"),raw]),format:"der",type:"spki"});process.exit(c.verify(null,fs.readFileSync(process.argv[2]),k,Buffer.from(fs.readFileSync(process.argv[3],"utf8").trim(),"base64"))?0:1)' "$PUBLIC_KEY" "$F" "$F.sig"; }
if command -v node >/dev/null 2>&1; then node_check || { echo "✗ the signing key doesn't match PUBLIC_KEY in release.conf" >&2; rm -f "$F.sig"; exit 1; }; fi
echo "✓ signed $F"
