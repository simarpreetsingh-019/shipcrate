#!/bin/sh
# shipcrate-installer: 1   (this marker lets shipcrate's tests know this is its installer; keep it if you edit)
# hello-ship installer for macOS and Linux (Windows: install.ps1). Reads the release manifest, downloads the file
# for this machine, checks it, installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/you/hello-ship/main/install.sh -o install.sh
#   less install.sh      # read it first: it's short
#   sh install.sh
#
# Checks before anything is installed:
#   1. the SHA-256 of the download matches the checksum in the release manifest
#   2. if the GitHub CLI is installed: the build attestation proves you/hello-ship published it
#   3. app: the code signature is intact and the bundle ID is none
# Options (environment): INSTALL_DIR=…  VERSION=1.2.3 (default: latest)  MANIFEST_URL=… (a mirror you trust)
set -eu
REPO='you/hello-ship'; TYPE='cli'; NAME='hello-ship'; BINARY='hello-ship'; BUNDLE_ID='none'
say() { printf '%s\n' "$*"; }
fail() { say "✗ $*"; say "  Nothing was installed."; exit 1; }
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }
case "$(uname -s)" in Darwin) OS=macos ;; Linux) OS=linux ;; *) fail "unsupported system $(uname -s) (on Windows use install.ps1)" ;; esac
case "$(uname -m)" in arm64|aarch64) ARCH=arm64 ;; x86_64|amd64) ARCH=x64 ;; *) fail "unsupported CPU $(uname -m)" ;; esac

if [ -n "${VERSION:-}" ]; then DEFAULT="https://github.com/$REPO/releases/download/v${VERSION#v}/latest.json"
else DEFAULT="https://github.com/$REPO/releases/latest/download/latest.json"; fi
MANIFEST_URL="${MANIFEST_URL:-$DEFAULT}"
TMP=$(mktemp -d); trap 'rm -rf "${TMP:?}"' EXIT
say "→ Reading the $NAME release manifest…"
curl -fsSL --proto '=https,file' "$MANIFEST_URL" -o "$TMP/latest.json" || fail "couldn't read $MANIFEST_URL"
TAG=$(sed -n 's/^ *"tag": *"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)
pick() { grep -E "^ *\"$1\": *\{" "$TMP/latest.json" | head -1; }
LINE=$(pick "$OS-$ARCH"); [ -n "$LINE" ] || LINE=$(pick "$OS"); [ -n "$LINE" ] || LINE=$(pick any)
[ -n "$LINE" ] || fail "release $TAG has no build for $OS-$ARCH."
field() { printf '%s' "$LINE" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }
ASSET=$(field name); URL=$(field url); EXPECTED=$(field sha256)
printf '%s' "$EXPECTED" | grep -Eq '^[0-9a-f]{64}$' || fail "the manifest has no valid checksum."
case "$ASSET" in */*|..*|"") fail "bad file name in the manifest." ;; esac
# Downloads come from this project's GitHub releases, unless you chose a MANIFEST_URL yourself.
[ "$MANIFEST_URL" = "$DEFAULT" ] && case "$URL" in "https://github.com/$REPO/releases/download/"*) ;; *) fail "unexpected download location: $URL" ;; esac

say "→ Downloading $NAME $TAG ($ASSET)…"
curl -fsSL --proto '=https,file' "$URL" -o "$TMP/$ASSET" || fail "download failed."
ACTUAL=$(sha256 "$TMP/$ASSET")
[ "$EXPECTED" = "$ACTUAL" ] || fail "checksum mismatch: the download doesn't match the release."
say "✓ Checksum matches the release ($ACTUAL)"
if command -v gh >/dev/null 2>&1 && [ "$MANIFEST_URL" = "$DEFAULT" ]; then
  if gh attestation verify "$TMP/$ASSET" --repo "$REPO" >/dev/null 2>&1; then say "✓ GitHub attestation: published by $REPO"
  else say "• GitHub attestation not checked (none for this release, or gh isn't signed in)"; fi
fi

if [ "$TYPE" = app ]; then
  [ "$OS" = macos ] || fail "$NAME is a macOS app."
  ditto -x -k "$TMP/$ASSET" "$TMP/x" || fail "couldn't unzip."
  APP=$(find "$TMP/x" -maxdepth 1 -name '*.app' | head -1); [ -n "$APP" ] || fail "no app inside the zip."
  [ "$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$BUNDLE_ID" ] || fail "unexpected app inside the zip."
  codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the app's signature is broken."
  say "✓ App signature intact"
  DEST="${INSTALL_DIR:-/Applications}"; [ -w "$DEST" ] || DEST="$HOME/Applications"; mkdir -p "$DEST"
  N=$(basename "$APP"); pkill -x "${N%.app}" 2>/dev/null && sleep 1 || true
  rm -rf "${DEST:?}/${N:?}"; ditto "$APP" "$DEST/$N"
  # Not notarized? The checks above did the verifying, so clear the download flag (as Homebrew does).
  xattr -dr com.apple.quarantine "$DEST/$N" 2>/dev/null || true
  say "✓ Installed to $DEST/$N"; [ -n "${NO_OPEN:-}" ] || open "$DEST/$N"
else
  mkdir -p "$TMP/x"; tar -xzf "$TMP/$ASSET" -C "$TMP/x" || fail "couldn't unpack."
  [ -f "$TMP/x/$BINARY" ] && [ ! -L "$TMP/x/$BINARY" ] || fail "no $BINARY inside the archive."
  DEST="${INSTALL_DIR:-}"; if [ -z "$DEST" ]; then if [ -w /usr/local/bin ]; then DEST=/usr/local/bin; else DEST="$HOME/.local/bin"; fi; fi
  mkdir -p "$DEST"
  [ -f "$DEST/$BINARY" ] && cp -p "$DEST/$BINARY" "$DEST/.$BINARY.old"   # previous version kept for rollback
  cp "$TMP/x/$BINARY" "$DEST/.$BINARY.new" && chmod 755 "$DEST/.$BINARY.new" && mv -f "$DEST/.$BINARY.new" "$DEST/$BINARY"
  xattr -d com.apple.quarantine "$DEST/$BINARY" 2>/dev/null || true
  say "✓ Installed $DEST/$BINARY ($TAG)"
  case ":$PATH:" in *":$DEST:"*) ;; *) say "  Add it to your PATH: export PATH=\"$DEST:\$PATH\"";; esac
fi
