#!/usr/bin/env bash
# Usage: host/install.sh <extension-id>
# Registers the protly native messaging host for the current user's Google Chrome.
set -euo pipefail
id="${1:?usage: host/install.sh <extension-id>}"
[[ "$id" =~ ^[a-p]{32}$ ]] || { echo "not a Chrome extension id: $id" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
host="$here/protly_host.py"
dir="$HOME/.config/google-chrome/NativeMessagingHosts"
mkdir -p "$dir"
chmod +x "$host"
cat > "$dir/com.northprot.protly.json" <<EOF
{
  "name": "com.northprot.protly",
  "description": "protly Claude API bridge",
  "path": "$host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$id/"]
}
EOF
echo "installed $dir/com.northprot.protly.json"
