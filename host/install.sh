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
# json.dumps, not a heredoc: a quote or backslash in the checkout path must stay inside "path".
python3 -I - "$host" "$id" > "$dir/com.northprot.protly.json" <<'PY'
import json, sys
host, ext = sys.argv[1], sys.argv[2]
print(json.dumps({
    'name': 'com.northprot.protly',
    'description': 'protly Claude API bridge',
    'path': host,
    'type': 'stdio',
    'allowed_origins': [f'chrome-extension://{ext}/'],
}, indent=2))
PY
echo "installed $dir/com.northprot.protly.json"
