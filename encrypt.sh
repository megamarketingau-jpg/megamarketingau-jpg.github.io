#!/bin/bash
# Encrypts all HTML files in public-encrypted/ → public/
#
# Password policy (since 26/05/2026):
#   - PER-CLIENT passwords. Same password for every report of a given client.
#   - Derived: HMAC-SHA256(ENCRYPTION_MASTER_SECRET, "client:<slug>") truncated to 16 chars.
#   - Client slug is extracted from filename pattern: YYYY-MM-<slug>-<type>.html
#   - Recognised slugs live in .client-slugs (sorted longest-first inside this script).
#   - Files that don't match any known client fall back to a path-derived password
#     (legacy behaviour). Add the client's slug to .client-slugs to upgrade.
#
# Lookup: bash get-password.sh <client-slug>   (or pass a file path)
# Run automatically via pre-commit hook. Run manually: bash encrypt.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$REPO_DIR/.env"
SRC="$REPO_DIR/public-encrypted"
DST="$REPO_DIR/public"
SLUG_FILE="$REPO_DIR/.client-slugs"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found. Cannot encrypt." >&2
  exit 1
fi

source "$ENV_FILE"

if [ -z "$ENCRYPTION_MASTER_SECRET" ]; then
  echo "ERROR: ENCRYPTION_MASTER_SECRET not set in .env" >&2
  exit 1
fi

client_password() {
  echo -n "client:$1" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $NF}' | cut -c1-16
}

path_password() {
  echo -n "$1" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $NF}' | cut -c1-16
}

# Extract client slug from a path like "reports/2026-05-amal-umrah-initial-meeting.html"
# by stripping the YYYY-MM- date prefix from the basename, then matching against
# .client-slugs (longest first, so multi-word slugs win over their substrings).
extract_slug() {
  local input="$1"
  local base="${input##*/}"
  base="${base%.html}"
  local stripped="${base#????-??-}"

  if [ ! -f "$SLUG_FILE" ]; then
    return 1
  fi

  local match=""
  while IFS= read -r slug; do
    [ -z "${slug// /}" ] && continue
    [[ "$slug" =~ ^# ]] && continue
    slug=$(echo "$slug" | xargs)
    [ -z "$slug" ] && continue
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

find "$SRC" -name "*.html" | while read -r src_file; do
  rel_path="${src_file#$SRC/}"
  rel_dir="$(dirname "$rel_path")"
  dst_dir="$DST/$rel_dir"

  if slug=$(extract_slug "$rel_path"); then
    password=$(client_password "$slug")
    mode="client:$slug"
  else
    password=$(path_password "$rel_path")
    mode="path-fallback"
  fi

  mkdir -p "$dst_dir"
  staticrypt "$src_file" \
    -p "$password" \
    -d "$dst_dir" \
    --short \
    --remember 30 \
    --config false

  echo "Encrypted: $rel_path  [$mode]"
done

git -C "$REPO_DIR" add "$DST" 2>/dev/null || true
echo "Encryption complete."
