#!/bin/bash
# Usage: bash get-password.sh reports/2026-05-labor-care-ads-report.html
# Returns the password for that file.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/.env"

if [ -z "$1" ]; then
  echo "Usage: bash get-password.sh <relative-file-path>"
  echo "Example: bash get-password.sh reports/2026-05-labor-care-ads-report.html"
  exit 1
fi

password=$(echo -n "$1" | openssl dgst -sha256 -hmac "$ENCRYPTION_MASTER_SECRET" | awk '{print $2}')
echo "File:     $1"
echo "Password: $password"
