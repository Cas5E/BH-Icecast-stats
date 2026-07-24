#!/usr/bin/env bash
# Generate secrets for .env (Linux / macOS / Git Bash)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
  echo ".env already exists at $ENV_FILE — not overwriting."
  exit 1
fi

rand() { openssl rand -hex 24; }

cp "$ROOT/.env.example" "$ENV_FILE"
sed -i.bak \
  -e "s|change-me-master-source|$(rand)|" \
  -e "s|change-me-relay|$(rand)|" \
  -e "s|change-me-admin|$(rand)|" \
  -e "s|change-me-api-token|$(rand)|" \
  "$ENV_FILE"
rm -f "$ENV_FILE.bak"

echo "Wrote $ENV_FILE with random secrets."
