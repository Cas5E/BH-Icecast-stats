#!/usr/bin/env bash
# Obtain Let's Encrypt cert and reload nginx (switches off self-signed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env"
  exit 1
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

: "${BH_DOMAIN:?}"
: "${LETSENCRYPT_EMAIL:?}"

echo "==> Requesting certificate for ${BH_DOMAIN}"
docker compose --profile ssl run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email "${LETSENCRYPT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  -d "${BH_DOMAIN}"

echo "==> Restarting proxy to pick up Let's Encrypt cert"
docker compose up -d --force-recreate proxy

echo "SSL ready: https://${BH_DOMAIN}"
