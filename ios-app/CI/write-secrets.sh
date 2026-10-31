#!/usr/bin/env bash
# Writes the gitignored ios-app/Sources/ProtlyKeyboard/Secrets.swift from PROTLY_API_KEY (the workflow passes the
# Actions secret to this step only) through ios-app/scripts/make-secrets.sh, which reads the key from
# $HOME/.config/protly/phone-api-key and checks that Secrets.swift is gitignored first. HOME is a mktemp folder
# (mode 700, key file 600) removed on every way out. Never prints the key, never traces (no set -x).
# Appends HAS_KEY=true or HAS_KEY=false to $GITHUB_ENV. An empty or unset secret keeps run-shots.sh's stand-in
# (empty key): every network check is SKIP no network key. Plan Task 2.1.
#
# Usage: PROTLY_API_KEY=... GITHUB_ENV=<file> ios-app/CI/write-secrets.sh
set -euo pipefail
set +x

here="$(cd "$(dirname "$0")" && pwd)"
: "${GITHUB_ENV:?GITHUB_ENV is not set}"

if [ -z "${PROTLY_API_KEY:-}" ]; then
  echo "PROTLY_API_KEY is empty: no network key, the CI stand-in keeps an empty key"
  echo "HAS_KEY=false" >> "$GITHUB_ENV"
  exit 0
fi

umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.config/protly"
printf '%s\n' "$PROTLY_API_KEY" > "$tmp/.config/protly/phone-api-key"  # printf is a builtin: no argv
# make-secrets.sh prints only paths and its own messages; its exit code decides.
if ! HOME="$tmp" bash "$here/../scripts/make-secrets.sh"; then
  echo "make-secrets.sh refused the key (see its message above); Secrets.swift not written" >&2
  exit 1
fi
echo "HAS_KEY=true" >> "$GITHUB_ENV"
