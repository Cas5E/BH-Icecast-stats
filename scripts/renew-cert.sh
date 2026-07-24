#!/usr/bin/env bash
# Renew Let's Encrypt certs and reload nginx proxy
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose run --rm certbot renew --webroot -w /var/www/certbot
docker compose exec proxy nginx -s reload
