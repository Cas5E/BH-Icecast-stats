#!/bin/bash
set -euo pipefail

: "${ICECAST_SOURCE_PASSWORD:?ICECAST_SOURCE_PASSWORD is required}"
: "${BH_DOMAIN:?BH_DOMAIN is required}"

ICECAST_SOURCE_AUTH_BASIC="$(printf 'source:%s' "$ICECAST_SOURCE_PASSWORD" | base64 -w0 2>/dev/null || printf 'source:%s' "$ICECAST_SOURCE_PASSWORD" | base64)"
export ICECAST_SOURCE_AUTH_BASIC
export BH_DOMAIN

LE_CERT="/etc/letsencrypt/live/${BH_DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/${BH_DOMAIN}/privkey.pem"
SELF_DIR="/etc/nginx/selfsigned"
SELF_CERT="${SELF_DIR}/fullchain.pem"
SELF_KEY="${SELF_DIR}/privkey.pem"

if [[ -f "${LE_CERT}" && -f "${LE_KEY}" ]]; then
  export SSL_CERTIFICATE="${LE_CERT}"
  export SSL_CERTIFICATE_KEY="${LE_KEY}"
  echo "Using Let's Encrypt certificate for ${BH_DOMAIN}"
else
  mkdir -p "${SELF_DIR}"
  if [[ ! -f "${SELF_CERT}" || ! -f "${SELF_KEY}" ]]; then
    echo "Creating temporary self-signed certificate for ${BH_DOMAIN}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3 \
      -keyout "${SELF_KEY}" \
      -out "${SELF_CERT}" \
      -subj "/CN=${BH_DOMAIN}" >/dev/null 2>&1
  fi
  export SSL_CERTIFICATE="${SELF_CERT}"
  export SSL_CERTIFICATE_KEY="${SELF_KEY}"
fi

# IP allowlist for /api /docs (comma/space separated). Always allow loopback.
ALLOW_FILE=/etc/nginx/bh_api_allow.conf
{
  echo "# Generated — do not edit"
  echo "allow 127.0.0.1;"
  echo "allow ::1;"
  if [[ -n "${BH_API_ALLOW_IPS:-}" ]]; then
    # shellcheck disable=SC2086
    for ip in $(echo "$BH_API_ALLOW_IPS" | tr ',;' ' '); do
      ip="$(echo "$ip" | xargs)"
      [[ -n "$ip" ]] || continue
      echo "allow ${ip};"
    done
  fi
  echo "deny all;"
} > "$ALLOW_FILE"
echo "API allowlist written to ${ALLOW_FILE}:"
cat "$ALLOW_FILE"

envsubst '${ICECAST_SOURCE_AUTH_BASIC} ${BH_DOMAIN} ${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
