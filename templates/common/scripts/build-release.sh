#!/bin/sh
# Build and package one release into dist/: "$ASSET" and "$ASSET.sha256". Used by release.sh and CI.
#   sh scripts/build-release.sh
set -eu
cd "$(dirname "$0")/.."
. ./release.conf
rm -rf ./dist && mkdir -p dist
echo "→ Building: $BUILD_CMD"
sh -c "$BUILD_CMD"
[ -e "$ARTIFACT" ] || { echo "✗ build output not found: $ARTIFACT (set ARTIFACT in release.conf)"; exit 1; }
case "$ASSET" in
  *.zip)
    if command -v ditto >/dev/null 2>&1; then ditto -c -k --keepParent "$ARTIFACT" "dist/$ASSET"   # keeps app signatures intact
    else (cd "$(dirname "$ARTIFACT")" && zip -qry "$OLDPWD/dist/$ASSET" "$(basename "$ARTIFACT")"); fi ;;
  *.tar.gz|*.tgz)
    STAGE=$(mktemp -d); trap 'rm -rf "${STAGE:?}"' EXIT
    if [ -d "$ARTIFACT" ]; then cp -R "$ARTIFACT"/. "$STAGE/"; else cp "$ARTIFACT" "$STAGE/$BINARY"; chmod 755 "$STAGE/$BINARY"; fi
    tar -czf "dist/$ASSET" -C "$STAGE" . ;;
  *) echo "✗ ASSET must end in .zip or .tar.gz"; exit 1 ;;
esac
if command -v shasum >/dev/null 2>&1; then (cd dist && shasum -a 256 "$ASSET" > "$ASSET.sha256")
else (cd dist && sha256sum "$ASSET" > "$ASSET.sha256"); fi
echo "✓ dist/$ASSET  sha256 $(cut -d' ' -f1 "dist/$ASSET.sha256")"
