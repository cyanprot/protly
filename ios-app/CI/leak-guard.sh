#!/usr/bin/env bash
# Refuses a run folder that contains an Anthropic key prefix anywhere (text or binary, any depth).
# Exit 0: clean. Exit 1: names the matching files (never their contents). Exit 2: the folder cannot be searched.
# publish-shots.sh calls it before anything leaves the runner (plan Task 1.6 step 2). Needs no secret.
#
# Usage: ios-app/CI/leak-guard.sh <run-dir>
set -u

dir="${1:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "leak-guard: no folder '$dir'" >&2
  exit 2
fi
matches="$(grep -rlF -e 'sk-ant-' -- "$dir")"
code=$?
case $code in
  1) exit 0 ;;
  0)
    echo "leak-guard: a key prefix was found in these files; nothing from this run is published:"
    printf '%s\n' "$matches" | while IFS= read -r f; do printf '  %s\n' "${f#"${dir%/}"/}"; done
    exit 1 ;;
  *)
    echo "leak-guard: grep failed (exit $code)" >&2
    exit 2 ;;
esac
