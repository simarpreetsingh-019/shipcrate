#!/bin/sh
# {{PRODUCT}} installer for people without Homebrew. Downloads the latest release from GitHub, checks it, installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/{{REPO}}/main/install.sh -o install.sh
#   less install.sh      # read it first: it's short
#   sh install.sh
#
# Checks before anything is installed:
#   1. the SHA-256 of the download matches the checksum published with the release
#   2. if the GitHub CLI is installed: the build attestation proves {{REPO}} published it
#   3. app: the code signature is intact and the bundle ID is {{BUNDLE_ID}}
set -eu
REPO='{{REPO}}'; ASSET='{{ASSET}}'; TYPE='{{TYPE}}'; NAME='{{PRODUCT}}'; BINARY='{{BINARY}}'; BUNDLE_ID='{{BUNDLE_ID}}'
say() { printf '%s\n' "$*"; }
fail() { say "✗ $*"; say "  Nothing was installed."; exit 1; }
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }

TMP=$(mktemp -d); trap 'rm -rf "${TMP:?}"' EXIT
say "→ Finding the latest $NAME release…"
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$TAG" ] || fail "couldn't reach GitHub."
BASE="https://github.com/$REPO/releases/download/$TAG"
say "→ Downloading $NAME $TAG…"
curl -fsSL "$BASE/$ASSET" -o "$TMP/$ASSET" || fail "download failed."
curl -fsSL "$BASE/$ASSET.sha256" -o "$TMP/$ASSET.sha256" || fail "couldn't get the checksum."
EXPECTED=$(cut -d' ' -f1 "$TMP/$ASSET.sha256"); ACTUAL=$(sha256 "$TMP/$ASSET")
[ "$EXPECTED" = "$ACTUAL" ] || fail "checksum mismatch: the download doesn't match the release."
say "✓ Checksum matches the release ($ACTUAL)"
if command -v gh >/dev/null 2>&1; then
  if gh attestation verify "$TMP/$ASSET" --repo "$REPO" >/dev/null 2>&1; then say "✓ GitHub attestation: published by $REPO"
  else say "• GitHub attestation not checked (none for this release, or gh isn't signed in)"; fi
fi

if [ "$TYPE" = app ]; then
  ditto -x -k "$TMP/$ASSET" "$TMP/x" || fail "couldn't unzip."
  APP=$(find "$TMP/x" -maxdepth 1 -name '*.app' | head -1); [ -n "$APP" ] || fail "no app inside the zip."
  [ "$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$BUNDLE_ID" ] || fail "unexpected app inside the zip."
  codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the app's signature is broken."
  say "✓ App signature intact"
  DEST=/Applications; [ -w "$DEST" ] || DEST="$HOME/Applications"; mkdir -p "$DEST"
  N=$(basename "$APP"); pkill -x "${N%.app}" 2>/dev/null && sleep 1 || true
  rm -rf "${DEST:?}/${N:?}"; ditto "$APP" "$DEST/$N"
  # Not notarized? The checks above did the verifying, so clear the download flag (as Homebrew does).
  xattr -dr com.apple.quarantine "$DEST/$N" 2>/dev/null || true
  say "✓ Installed to $DEST/$N"; open "$DEST/$N"
else
  mkdir -p "$TMP/x"; tar -xzf "$TMP/$ASSET" -C "$TMP/x" || fail "couldn't unpack."
  [ -f "$TMP/x/$BINARY" ] || fail "no $BINARY inside the archive."
  DEST="${INSTALL_DIR:-}"; if [ -z "$DEST" ]; then if [ -w /usr/local/bin ]; then DEST=/usr/local/bin; else DEST="$HOME/.local/bin"; fi; fi
  mkdir -p "$DEST"
  [ -f "$DEST/$BINARY" ] && cp "$DEST/$BINARY" "$DEST/.$BINARY.old"   # previous version kept for rollback
  cp "$TMP/x/$BINARY" "$DEST/.$BINARY.new" && chmod 755 "$DEST/.$BINARY.new" && mv -f "$DEST/.$BINARY.new" "$DEST/$BINARY"
  xattr -d com.apple.quarantine "$DEST/$BINARY" 2>/dev/null || true
  say "✓ Installed $DEST/$BINARY"
  case ":$PATH:" in *":$DEST:"*) ;; *) say "  Add it to your PATH: export PATH=\"$DEST:\$PATH\"";; esac
fi
