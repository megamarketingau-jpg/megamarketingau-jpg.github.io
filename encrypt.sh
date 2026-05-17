#!/bin/bash
# Encrypts all HTML files in public-encrypted/ → public/
# Passwords are derived per-file: HMAC-SHA256(master_secret, file_path)
# Run automatically via pre-commit hook. Run manually: bash encrypt.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$REPO_DIR/.env"
SRC="$REPO_DIR/public-encrypted"
DST="$REPO_DIR/public"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found. Cannot encrypt." >&2
  exit 1
fi

source "$ENV_FILE"

if [ -z "$ENCRYPTION_MASTER_SECRET" ]; then
  echo "ERROR: ENCRYPTION_MASTER_SECRET not set in .env" >&2
  exit 1
fi

find "$SRC" -name "*.html" | while read -r src_file; do
  rel_path="${src_file#$SRC/}"
  dst_file="$DST/$rel_path"
  dst_dir="$(dirname "$dst_file")"

  # Derive per-file password
  password=$(echo -n "$rel_path" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $2}')

  mkdir -p "$dst_dir"
  staticrypt "$src_file" --password "$password" \
    --short \
    --template-title "Mega Marketing | Access Required" \
    --template-instructions "Enter the password provided by your Mega Marketing account manager." \
    --output "$dst_file" \
    --remember 30 \
    2>/dev/null

  echo "Encrypted: $rel_path"
done

# Stage the public/ output
git -C "$REPO_DIR" add "$DST" 2>/dev/null || true
echo "Encryption complete."
