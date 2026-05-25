#!/bin/bash
# Lookup the password for a client (preferred) or a published report file.
#
# Usage:
#   bash get-password.sh <client-slug>                        # preferred
#   bash get-password.sh reports/YYYY-MM-<slug>-<type>.html   # also accepted
#   bash get-password.sh                                      # list every client + password
#
# Same password per client across every report. The encryption side derives the
# same value from .client-slugs + .env's ENCRYPTION_MASTER_SECRET, so this is
# a pure lookup — no separate password store.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/.env"
SLUG_FILE="$REPO_DIR/.client-slugs"

client_password() {
  echo -n "client:$1" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $NF}' | cut -c1-16
}

path_password() {
  echo -n "$1" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $NF}' | cut -c1-16
}

extract_slug() {
  local input="$1"
  local base="${input##*/}"
  base="${base%.html}"
  local stripped="${base#????-??-}"

  [ ! -f "$SLUG_FILE" ] && return 1

  local match=""
  while IFS= read -r slug; do
    [ -z "${slug// /}" ] && continue
    [[ "$slug" =~ ^# ]] && continue
    slug=$(echo "$slug" | xargs)
    [ -z "$slug" ] && continue
    # Exact slug input
    if [ "$input" = "$slug" ]; then
      match="$slug"
      break
    fi
    # Slug inside a filename
    case "$stripped" in
      "$slug"|"$slug"-*)
        match="$slug"
        break
        ;;
    esac
  done < <(awk '!/^#/ && NF { print length, $0 }' "$SLUG_FILE" | sort -rn | sed 's/^[0-9]* //')

  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  return 1
}

if [ -z "$1" ]; then
  printf "%-26s %s\n" "CLIENT" "PASSWORD"
  printf "%-26s %s\n" "------" "--------"
  awk '!/^#/ && NF { print }' "$SLUG_FILE" | xargs -n1 | sort -u | while read -r slug; do
    [ -z "$slug" ] && continue
    printf "%-26s %s\n" "$slug" "$(client_password "$slug")"
  done
  exit 0
fi

if slug=$(extract_slug "$1"); then
  echo "Client:   $slug"
  echo "Password: $(client_password "$slug")"
  echo ""
  echo "Reuse this password for every report issued to this client."
else
  # Fallback: legacy path-derived password (only useful for already-encrypted legacy files)
  echo "WARN: no client slug matched '$1'." >&2
  echo "      Falling back to legacy file-path-derived password (legacy reports only)." >&2
  echo "      To upgrade: add the slug to .client-slugs and re-encrypt by pushing a commit." >&2
  echo ""
  echo "File:     $1"
  echo "Password: $(path_password "$1")"
fi
