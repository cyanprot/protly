#!/usr/bin/env bash
# Builds the signed iOS Shortcut and drops it in Google Drive for import on the iPhone.
# Signing goes through HubSign (no Mac). The file holds no API key and no memos.
set -euo pipefail
cd "$(dirname "$0")/.."
CHERRI="${CHERRI:-$HOME/.local/opt/cherri-2.3.0/cherri}"
node scripts/build-ios-template.mjs
out="$(mktemp -d)"
cp ios/ig-translate.cherri "$out/"
(cd "$out" && "$CHERRI" ig-translate.cherri --hubsign --share=anyone --no-ansi)
[ "$(head -c 4 "$out/ig-translate.shortcut")" = "AEA1" ] || { echo "not signed" >&2; exit 1; }
cp "$out/ig-translate.shortcut" "$HOME/GoogleDrive/IG Translate.shortcut"
echo "Copied to ~/GoogleDrive/IG Translate.shortcut"
