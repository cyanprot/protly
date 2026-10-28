#!/usr/bin/env bash
# Usage: host/install.sh <extension-id>
# Registers the ig-translate native messaging host for the current user's Google Chrome.
set -euo pipefail
id="${1:?usage: host/install.sh <extension-id>}"
[[ "$id" =~ ^[a-p]{32}$ ]] || { echo "not a Chrome extension id: $id" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
host="$here/ig_translate_host.py"
dir="$HOME/.config/google-chrome/NativeMessagingHosts"
mkdir -p "$dir"
chmod +x "$host"
cat > "$dir/com.northprot.ig_translate.json" <<EOF
{
  "name": "com.northprot.ig_translate",
  "description": "ig-translate Claude API bridge",
  "path": "$host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$id/"]
}
EOF
echo "installed $dir/com.northprot.ig_translate.json"
