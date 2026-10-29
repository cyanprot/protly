#!/usr/bin/env bash
# Samples Tatoeba Korean and English sentences into Corpus/ (deterministic: every Nth line of the export).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
for l in kor eng; do
  curl -fL -o "$tmp/$l.tsv.bz2" "https://downloads.tatoeba.org/exports/per_language/$l/${l}_sentences.tsv.bz2"
done
bzcat "$tmp/kor.tsv.bz2" | awk -F'\t' 'NR%8==0{print $3}' > Corpus/tatoeba-kor.txt
bzcat "$tmp/eng.tsv.bz2" | awk -F'\t' 'NR%900==0{print $3}' > Corpus/tatoeba-eng.txt
rm -rf "$tmp"
wc -l Corpus/tatoeba-*.txt
