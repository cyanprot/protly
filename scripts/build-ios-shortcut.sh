#!/usr/bin/env bash
# Builds the signed iOS Shortcut and drops it in Google Drive for import on the iPhone.
# Signing goes through HubSign (no Mac). The file holds no API key and no memos.
set -euo pipefail
cd "$(dirname "$0")/.."
CHERRI="${CHERRI:-$HOME/.local/opt/cherri-2.3.0/cherri}"
node scripts/build-ios-template.mjs
out="$(mktemp -d)"
build() { # $1 source basename, $2 name in Google Drive
  cp "ios/$1.cherri" "$out/"
  (cd "$out" && "$CHERRI" "$1.cherri" --hubsign --share=anyone --no-ansi)
  [ "$(head -c 4 "$out/$1.shortcut")" = "AEA1" ] || { echo "$1 not signed" >&2; exit 1; }
  cp "$out/$1.shortcut" "$HOME/GoogleDrive/$2.shortcut"
  echo "Copied to ~/GoogleDrive/$2.shortcut"
}
build protly "Protly"
build protly-write "Protly Write"
