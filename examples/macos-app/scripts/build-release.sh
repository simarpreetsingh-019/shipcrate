#!/bin/sh
# Build and package one target into dist/: "<asset>" and "<asset>.sha256". Used by release.sh and CI.
#   sh scripts/build-release.sh [target]       (default: this machine's target, or the only one in TARGETS)
# A target is built natively on a matching machine; CI builds each target on its own runner.
set -eu
cd "$(dirname "$0")/.."
. ./release.conf; . scripts/lib.sh
T="${1:-}"
if [ -z "$T" ]; then
  set -- $TARGETS
  if [ $# -eq 1 ]; then T=$1; else T=$(host_target); fi
fi
case " $TARGETS " in *" $T "*) ;; *) echo "✗ target $T isn't in TARGETS ($TARGETS)"; exit 1 ;; esac
case "$T" in
  any) ;;
  macos) [ "$(uname -s)" = Darwin ] || { echo "✗ a macOS app builds on macOS"; exit 1; } ;;
  *) [ "$T" = "$(host_target)" ] || [ -n "${CROSS_OK:-}" ] || { echo "✗ build $T on a $T machine (CI does this), or set CROSS_OK=1 if BUILD_CMD cross-compiles"; exit 1; } ;;
esac
A=$(asset_for "$T")
mkdir -p dist && rm -f "dist/$A" "dist/$A.sha256"
echo "→ Building $T: $BUILD_CMD"
TARGET="$T" sh -c "$BUILD_CMD"
SRC="$ARTIFACT"; BIN="$BINARY"
case "$T" in windows-*) [ -e "$SRC.exe" ] && SRC="$SRC.exe"; BIN="$BINARY.exe" ;; esac
[ -e "$SRC" ] || { echo "✗ build output not found: $SRC (set ARTIFACT in release.conf)"; exit 1; }
STAGE=$(mktemp -d); trap 'rm -rf "${STAGE:?}"' EXIT
case "$A" in
  *.zip)
    if [ "$TYPE" = app ]; then ditto -c -k --keepParent "$SRC" "dist/$A"   # keeps the app's signature intact
    else
      if [ -d "$SRC" ]; then cp -R "$SRC"/. "$STAGE/"; else cp "$SRC" "$STAGE/$BIN"; fi
      if command -v zip >/dev/null 2>&1; then (cd "$STAGE" && zip -qr "$OLDPWD/dist/$A" .)
      else powershell -NoProfile -Command "Compress-Archive -Path '$STAGE/*' -DestinationPath 'dist/$A'"; fi
    fi ;;
  *.tar.gz|*.tgz)
    if [ -d "$SRC" ]; then cp -R "$SRC"/. "$STAGE/"; else cp "$SRC" "$STAGE/$BIN"; chmod 755 "$STAGE/$BIN"; fi
    tar -czf "dist/$A" -C "$STAGE" . ;;
  *) echo "✗ ASSET must end in .zip or .tar.gz"; exit 1 ;;
esac
(cd dist && printf '%s  %s\n' "$(sha256_of "$A")" "$A" > "$A.sha256")
echo "✓ dist/$A  sha256 $(cut -d' ' -f1 "dist/$A.sha256")"
