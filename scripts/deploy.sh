#!/usr/bin/env bash
#
# Bootstrap TLS + start BH-Icecast on a Linux host (Docker).
# Run on the server from the project root.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example and set secrets first."
  exit 1
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

: "${BH_DOMAIN:?}"
: "${LETSENCRYPT_EMAIL:?}"
: "${ICECAST_SOURCE_PASSWORD:?}"
: "${BH_API_TOKEN:?}"

echo "==> Ensuring Docker is available"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

if systemctl is-active --quiet nginx 2>/dev/null; then
  echo "==> Stopping host nginx (Docker proxy will own 80/443)"
  systemctl stop nginx || true
  systemctl disable nginx || true
fi
if systemctl is-active --quiet apache2 2>/dev/null; then
  systemctl stop apache2 || true
fi

echo "==> Ensuring certificate material exists"
docker compose run --rm --entrypoint sh certbot -c "
set -e
DOMAIN='${BH_DOMAIN}'
LIVE=\"/etc/letsencrypt/live/\${DOMAIN}\"
mkdir -p \"\${LIVE}\"
if [ ! -f \"\${LIVE}/fullchain.pem\" ]; then
  echo 'Creating temporary self-signed certificate...'
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout \"\${LIVE}/privkey.pem\" \
    -out \"\${LIVE}/fullchain.pem\" \
    -subj \"/CN=\${DOMAIN}\"
  cp \"\${LIVE}/fullchain.pem\" \"\${LIVE}/chain.pem\"
fi
"

echo "==> Building images"
docker compose build

echo "==> Starting stack"
docker compose up -d

echo "==> Waiting for nginx on :80"
for i in $(seq 1 45); do
  if curl -fsSI "http://127.0.0.1/" >/dev/null 2>&1; then
    echo "nginx is responding"
    break
  fi
  sleep 2
  if [[ "$i" -eq 45 ]]; then
    docker compose ps
    docker compose logs --tail=100 proxy
    exit 1
  fi
done

echo "==> Obtaining / refreshing Let's Encrypt certificate"
docker compose run --rm --entrypoint sh certbot -c "
DOMAIN='${BH_DOMAIN}'
LIVE=\"/etc/letsencrypt/live/\${DOMAIN}\"
if [ -f \"\${LIVE}/fullchain.pem\" ] && openssl x509 -in \"\${LIVE}/fullchain.pem\" -noout -issuer 2>/dev/null | grep -qi \"Let's Encrypt\"; then
  echo 'Valid Let'\''s Encrypt certificate already present'
  exit 0
fi
rm -rf \"/etc/letsencrypt/live/\${DOMAIN}\" \
       \"/etc/letsencrypt/archive/\${DOMAIN}\" \
       \"/etc/letsencrypt/renewal/\${DOMAIN}.conf\"
exit 0
"

docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  --cert-name "$BH_DOMAIN" \
  -d "$BH_DOMAIN"

echo "==> Reloading nginx"
docker compose exec proxy nginx -s reload

echo "==> Waiting for API health over HTTPS"
for i in $(seq 1 30); do
  if curl -fsS "https://${BH_DOMAIN}/health" >/dev/null 2>&1; then
    echo "Healthy: https://${BH_DOMAIN}/health"
    break
  fi
  sleep 2
  if [[ "$i" -eq 30 ]]; then
    echo "API not healthy yet — check: docker compose logs"
    docker compose ps
    docker compose logs --tail=80 proxy api
    exit 1
  fi
done

CRON_LINE="15 3 * * * cd ${ROOT} && ./scripts/renew-cert.sh >> /var/log/bh-icecast-renew.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'bh-icecast-renew' || true; echo "$CRON_LINE") | crontab -

echo
echo "BH-Icecast is up."
echo "  Listen / encode : https://${BH_DOMAIN}/<mount>"
echo "  API             : https://${BH_DOMAIN}/api/v1/mounts"
echo "  Docs            : https://${BH_DOMAIN}/docs"
