#!/bin/sh
# Turn on signed updates: make an Ed25519 key pair for this project.
#   sh scripts/keygen.sh [--rotate] [--no-secret]
# · private key → ~/.config/shipcrate/<owner>-<repo>.ed25519.pem (only on this machine, chmod 600; back it up
#   in your password manager) and, if you say yes, the GitHub secret SHIPCRATE_SIGNING_KEY for the release workflow
# · public key → PUBLIC_KEY in release.conf and into every updater file marked "shipcrate:public-key"
# From then on every latest.json is signed, and apps/CLIs refuse a manifest whose signature doesn't match.
# Never commit the private key. If it leaks: run keygen again, release, and old copies keep trusting only the old key
# until they update, so rotate early.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
if [ -t 0 ] && ! printf '%s' " $* " | grep -q -e ' --yes ' -e ' --no-secret '; then
  cat <<'TXT'
Signed updates: what changes
  Today:  your app trusts latest.json when it comes over HTTPS from your GitHub releases and its checksums match.
  After:  it also needs your Ed25519 signature on latest.json. Someone who got into your GitHub account, a
          release or a mirror still couldn't push an update without your private key.
  Users:  nothing changes for copies already installed until they take the next update; from then on they check.
  You:    keep the private key safe (a password manager is fine). If it's lost, users must reinstall once.
          The key never goes into the repository.
TXT
  printf 'Turn on signed updates for this project? [y/N] '; read -r ok
  case "$ok" in y|Y|yes) ;; *) echo "No change."; exit 0 ;; esac
fi
DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shipcrate"; KEY="$DIR/$(printf '%s' "$REPO" | tr '/' '-').ed25519.pem"
if [ -f "$KEY" ] && ! printf '%s' " $* " | grep -q ' --rotate '; then echo "A key already exists: $KEY (use --rotate to replace it)"; else
  mkdir -p "$DIR" && chmod 700 "$DIR"; umask 077
  if openssl version 2>/dev/null | grep -q '^OpenSSL [3-9]'; then openssl genpkey -algorithm ed25519 -out "$KEY"
  elif command -v node >/dev/null 2>&1; then node -e 'const c=require("crypto");process.stdout.write(c.generateKeyPairSync("ed25519").privateKey.export({type:"pkcs8",format:"pem"}))' > "$KEY"
  else echo "✗ needs OpenSSL 3 (brew install openssl@3) or Node 18+"; exit 1; fi
  chmod 600 "$KEY"; echo "✓ private key: $KEY  (back it up somewhere safe; never commit it)"
fi
if openssl version 2>/dev/null | grep -q '^OpenSSL [3-9]'; then PUB=$(openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | openssl base64 -A)
else PUB=$(node -e 'const c=require("crypto"),fs=require("fs");process.stdout.write(c.createPublicKey(fs.readFileSync(process.argv[1])).export({type:"spki",format:"der"}).subarray(-32).toString("base64"))' "$KEY"); fi
# release.conf
if grep -q '^PUBLIC_KEY=' release.conf; then sed "s#^PUBLIC_KEY=.*#PUBLIC_KEY='$PUB'#" release.conf > release.conf.new && mv release.conf.new release.conf
else printf "\n# Signed updates (scripts/keygen.sh): apps and CLIs only trust a latest.json signed by this key.\nPUBLIC_KEY='%s'\n" "$PUB" >> release.conf; fi
# every updater copy in the project
for f in $(grep -rls 'shipcrate:public-key' --include='*.rs' --include='*.py' --include='*.js' --include='*.ts' --include='*.swift' . 2>/dev/null | grep -v node_modules); do
  # "|" as the sed delimiter: base64 keys contain "/" and "+"
  sed -E "/shipcrate:public-key/s|\"[A-Za-z0-9+/=]*\"|\"$PUB\"|" "$f" > "$f.new" && mv "$f.new" "$f"
  grep -q "\"$PUB\".*shipcrate:public-key" "$f" || { echo "✗ couldn't write the public key into $f" >&2; exit 1; }
  echo "✓ public key → $f"
done
echo "✓ PUBLIC_KEY in release.conf: $PUB"
case " $* " in *" --no-secret "*) NOSECRET=1 ;; *) NOSECRET=0 ;; esac
if [ $NOSECRET = 0 ] && command -v gh >/dev/null 2>&1; then
  printf 'Store the private key as the GitHub secret SHIPCRATE_SIGNING_KEY on %s (needed for CI releases)? [y/N] ' "$REPO"
  read -r ok </dev/tty 2>/dev/null || ok=n
  case "$ok" in y|Y|yes) gh secret set SHIPCRATE_SIGNING_KEY --repo "$REPO" < "$KEY" && echo "✓ secret set" ;; *) echo "• skipped: later run  gh secret set SHIPCRATE_SIGNING_KEY --repo $REPO < $KEY" ;; esac
fi
echo "Commit release.conf and the updater files, then release as usual. Releases are now signed."
