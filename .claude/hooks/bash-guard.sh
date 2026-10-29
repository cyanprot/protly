#!/usr/bin/env bash
# PreToolUse:Bash guard.
# Blocks only commands that are unrecoverable at the system level.
# Anything confined to $HOME, /tmp, or a project tree is allowed through.
# Exit 2 + stderr = block. Exit 0 = allow.

set -uo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

deny() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 2
}

# System directories whose recursive removal is unrecoverable.
SYSDIRS='etc|usr|bin|sbin|boot|lib|lib64|var|opt|sys|proc|dev|run|root'

# rm with both -r and -f (any flag order/grouping) targeting / or a system dir.
# Trailing context requires /, whitespace, or end-of-string so that
# `rm -rf /home/cyan/.cache` and `rm -rf /tmp/x` pass (home roots: see HOMEROOT below).
RM_FLAGS='-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*|-r[[:space:]]+-f|-f[[:space:]]+-r'
if printf '%s' "$CMD" | grep -qEi "\brm[[:space:]]+($RM_FLAGS)[[:space:]]+[\"']?(/|/\*|~|\\\$HOME)[\"']?([[:space:]]|;|&|\||$)"; then
  deny "recursive force-delete of / or \$HOME root"
fi
# Home roots: /home, /home/<user>, ~/ and $HOME/ (with optional trailing / or /*).
# The rule above misses `rm -rf /home`, `rm -rf ~/` and `rm -rf /home/cyan`.
HOMEROOT='(~|\$HOME|\$\{HOME\}|/home(/[^/[:space:]]+)?)/?\*?'
if printf '%s' "$CMD" | grep -qEi "\brm[[:space:]]+($RM_FLAGS)[[:space:]]+[\"']?$HOMEROOT[\"']?([[:space:]]|;|&|\||$)"; then
  deny "recursive force-delete of a home directory root"
fi
if printf '%s' "$CMD" | grep -qEi "\brm[[:space:]]+($RM_FLAGS)[[:space:]]+[\"']?/($SYSDIRS)([/[:space:]\"';&|]|$)"; then
  deny "recursive force-delete of a system directory"
fi

# Filesystem / block-device destruction.
printf '%s' "$CMD" | grep -qEi '\bmkfs(\.[a-z0-9]+)?\b' && deny "mkfs would format a filesystem"
printf '%s' "$CMD" | grep -qEi '\bdd\b.*\bof=/dev/(sd|nvme|vd|hd|mmcblk)' && deny "dd writing to a raw block device"
printf '%s' "$CMD" | grep -qEi '>[[:space:]]*/dev/(sd|nvme|vd|hd|mmcblk)' && deny "redirect into a raw block device"
printf '%s' "$CMD" | grep -qEi '\b(wipefs|shred)\b.*(/dev/|--all)' && deny "wipefs/shred against a device"

# Permission nukes on system roots.
printf '%s' "$CMD" | grep -qEi '\bchmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*777[[:space:]]+/([[:space:]]|$)' && deny "chmod 777 on /"
printf '%s' "$CMD" | grep -qEi "\bchown[[:space:]]+-R[[:space:]]+[^[:space:]]+[[:space:]]+/([[:space:]]|$)" && deny "recursive chown on /"

# Irreversible remote history rewrite. --force-with-lease is allowed.
if printf '%s' "$CMD" | grep -qEi '\bgit[[:space:]]+push\b' \
   && printf '%s' "$CMD" | grep -qEi '(--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$))' \
   && ! printf '%s' "$CMD" | grep -qEi -- '--force-with-lease'; then
  deny "git push --force (use --force-with-lease)"
fi

# Skipping commit hooks defeats the project's typecheck/lint gate.
printf '%s' "$CMD" | grep -qEi -- '--no-verify\b' && deny "--no-verify skips the pre-commit gate"

# Destructive SQL.
printf '%s' "$CMD" | grep -qEi '\b(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+TABLE)\b' && deny "destructive SQL statement"

# SECRETS: credential paths may be listed or chmod'd, never read, copied, encoded or uploaded.
# Covered (any prefix spelling: ~/, $HOME/, /home/cyan/, relative): .credentials.json,
# .config/gws, .local/state/brightspace-mcp and _archive, storage_state.json, and any
# file named exactly .env (not .env.example, .envrc, env.sh).
# If the command text names one, every segment (split on ; && || | & $( ` ( ) { }) must
# start with a metadata verb; a segment naming the path must be metadata or echo-like.
SECRET_RE='\.credentials\.json|storage_state\.json|\.config/gws([/[:space:]"'"'"'*;&|)]|$)|\.local/state/(brights|_a)|(^|[/[:space:]"'"'"'=<>:(`*])\.env(\.(local|production|development|prod|dev|staging|test))?([[:space:]"'"'"';&|)<>*]|$)'
SECRET_META=' ls stat du chmod chown chgrp mkdir rm rmdir test [ [[ find realpath readlink dirname basename '
SECRET_BENIGN=' echo printf true false : pwd date exit return fi done else then do esac wc head tail sort uniq grep cut tr '
if printf '%s' "$CMD" | grep -qE "$SECRET_RE"; then
  SEGS=$(printf '%s' "$CMD" \
    | sed -E 's/[0-9]*>&[0-9-]+//g; s/&>>?/>/g; s#[0-9]*>>?[[:space:]]*/dev/null##g' \
    | sed -E 's/&&|\|\||[;|&(){}`]|\$\(/\n/g')
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    while [[ $seg =~ ^(if|then|else|elif|do|while|until|!|time|sudo|command|nohup|nice|exec)[[:space:]]+(.*)$ ]]; do
      seg="${BASH_REMATCH[2]}"
    done
    [ -z "$seg" ] && continue
    verb="${seg%%[[:space:]]*}"; verb="${verb#[\"\']}"; verb="${verb##*/}"
    here=0
    printf '%s' "$seg" | grep -qE "$SECRET_RE" && here=1
    if [[ $SECRET_META == *" $verb "* ]]; then
      if [ "$here" = 1 ]; then
        [[ $seg == *"<"* || $seg == *">"* ]] && deny "SECRETS rule: redirection touching a credential path; use ls/stat for metadata"
        [ "$verb" = find ] && printf '%s' "$seg" | grep -qE -- '-(exec|execdir|ok|okdir|fprint0?|fls|print0)\b' \
          && deny "SECRETS rule: find with -exec/-print0 on a credential path; use ls/stat for metadata"
      fi
    elif [[ $SECRET_BENIGN == *" $verb "* ]]; then
      if [ "$here" = 1 ]; then
        case "$verb" in echo|printf|true|false|:) [[ $seg == *"<"* || $seg == *">"* ]] \
          && deny "SECRETS rule: redirection touching a credential path; use ls/stat for metadata" ;;
        *) deny "SECRETS rule, reading credential paths is blocked; use ls/stat for metadata" ;;
        esac
      fi
    else
      deny "SECRETS rule, reading credential paths is blocked; use ls/stat for metadata"
    fi
  done <<<"$SEGS"
fi

exit 0
