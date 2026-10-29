#!/usr/bin/env bash
# Commits one run's PNGs, logs and report.txt to the orphan branch ci-shots under <dest>, and nothing else.
# Retries fetch, re-apply on the new tip, push up to 3 times (another branch's run may push in between).
#
# Usage: ios-app/CI/publish-shots.sh <run-dir> <dest, e.g. runs/abc1234-7>
# Env: GH_TOKEN (the workflow's GITHUB_TOKEN), GITHUB_REPOSITORY, GITHUB_SHA.
set -euo pipefail

src="$(cd "$1" && pwd)"
dest="$2"
if [ ! -f "$src/report.txt" ]; then
  printf 'STATUS build-failed\nrun-shots.sh stopped before writing a report; see the workflow log.\n' > "$src/report.txt"
fi

repo="${RUNNER_TEMP:-/tmp}/ci-shots-publish"
rm -rf "$repo"
git init -q "$repo"
cd "$repo"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

for attempt in 1 2 3; do
  if git fetch -q --depth 1 origin ci-shots 2> /dev/null; then
    git checkout -q -f -B ci-shots FETCH_HEAD
  else
    git symbolic-ref HEAD refs/heads/ci-shots  # first run: the orphan branch starts here
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  find "$src" -maxdepth 1 -type f \( -name '*.png' -o -name '*.txt' \) -exec cp {} "$dest"/ \;
  git add -A "$dest"
  git commit -q -m "shots: $dest (source ${GITHUB_SHA})"
  if git push -q origin HEAD:refs/heads/ci-shots; then
    echo "published $dest to ci-shots"
    exit 0
  fi
  echo "push attempt $attempt failed; refetching"
  sleep $((attempt * 5))
done
echo "could not publish to ci-shots" >&2
exit 1
