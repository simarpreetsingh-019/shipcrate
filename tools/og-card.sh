#!/bin/sh
# Render tools/og-card.html to docs/assets/og.png (1200×630) with headless Chrome.
set -eu
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1200,630 --virtual-time-budget=4000 \
  --screenshot="$PWD/docs/assets/og.png" "file://$PWD/tools/og-card.html" 2>/dev/null
echo "✓ docs/assets/og.png"
