#!/usr/bin/env bash
# Deploy one BH-Icecast instance (env file) to a remote Linux host.
# Usage:
#   bash scripts/deploy-instance.sh --env deployments/stream.example.com.env
#   bash scripts/deploy-instance.sh --env deployments/foo.env --host 1.2.3.4 --skip-ssl
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE=""
SSH_HOST=""
SSH_USER=""
REMOTE_DIR=""
SKIP_SSL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="${2:?}"; shift 2 ;;
    --host) SSH_HOST="${2:?}"; shift 2 ;;
    --user) SSH_USER="${2:?}"; shift 2 ;;
    --remote-dir) REMOTE_DIR="${2:?}"; shift 2 ;;
    --skip-ssl) SKIP_SSL=1; shift ;;
    -h|--help)
      sed -n '2,7p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

: "${ENV_FILE:?--env is required}"
if [[ ! -f "$ENV_FILE" ]]; then
  # allow path relative to repo root
  if [[ -f "$ROOT/$ENV_FILE" ]]; then
    ENV_FILE="$ROOT/$ENV_FILE"
  else
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
  fi
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

SSH_HOST="${SSH_HOST:-${DEPLOY_SSH_HOST:-}}"
SSH_USER="${SSH_USER:-${DEPLOY_SSH_USER:-root}}"
REMOTE_DIR="${REMOTE_DIR:-${DEPLOY_REMOTE_DIR:-/opt/bh-icecast}}"

: "${SSH_HOST:?Set --host or DEPLOY_SSH_HOST in the env file}"
: "${BH_DOMAIN:?BH_DOMAIN missing in env file}"
: "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL missing in env file}"
: "${BH_API_TOKEN:?BH_API_TOKEN missing in env file}"

ssh_cmd() {
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
  else
    ssh -o StrictHostKeyChecking=accept-new "$@"
  fi
}

scp_cmd() {
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -e scp -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
  else
    scp -o StrictHostKeyChecking=accept-new "$@"
  fi
}

echo "==> Target ${SSH_USER}@${SSH_HOST}  domain=${BH_DOMAIN}  dir=${REMOTE_DIR}"

echo "==> Ensuring Docker on remote"
ssh_cmd "${SSH_USER}@${SSH_HOST}" bash -s <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker compose version >/dev/null
REMOTE

echo "==> Syncing project"
ssh_cmd "${SSH_USER}@${SSH_HOST}" "mkdir -p '${REMOTE_DIR}'"

TAR="/tmp/bh-icecast-${BH_DOMAIN}.tgz"
tar czf "$TAR" \
  --exclude .git --exclude .venv --exclude api/.venv \
  --exclude data --exclude api/data --exclude __pycache__ \
  --exclude 'deployments/*.env' \
  --exclude .env \
  -C "$ROOT" .

scp_cmd "$TAR" "${SSH_USER}@${SSH_HOST}:/tmp/bh-icecast-deploy.tgz"
rm -f "$TAR"

ssh_cmd "${SSH_USER}@${SSH_HOST}" \
  "tar xzf /tmp/bh-icecast-deploy.tgz -C '${REMOTE_DIR}' && rm -f /tmp/bh-icecast-deploy.tgz"

echo "==> Uploading instance .env"
scp_cmd "$ENV_FILE" "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/.env"
ssh_cmd "${SSH_USER}@${SSH_HOST}" "chmod 600 '${REMOTE_DIR}/.env'"

echo "==> Build & start"
ssh_cmd "${SSH_USER}@${SSH_HOST}" bash -s <<REMOTE
set -euo pipefail
cd '${REMOTE_DIR}'
chmod +x scripts/*.sh nginx/docker-entrypoint.sh icecast/docker-entrypoint.sh 2>/dev/null || true
if systemctl is-active --quiet nginx 2>/dev/null; then
  systemctl stop nginx || true
  systemctl disable nginx || true
fi
docker compose up -d --build
sleep 4
docker compose ps
REMOTE

if [[ "$SKIP_SSL" -eq 0 ]]; then
  echo "==> Let's Encrypt (${BH_DOMAIN})"
  ssh_cmd "${SSH_USER}@${SSH_HOST}" "cd '${REMOTE_DIR}' && bash scripts/init-ssl.sh"
else
  echo "==> Skipping SSL (--skip-ssl)"
fi

echo
echo "Deployed ${BH_DOMAIN}"
echo "  Streams : https://${BH_DOMAIN}/<mount>"
echo "  API     : https://${BH_DOMAIN}/api/v1/mounts  (Bearer BH_API_TOKEN)"
echo "  Docs    : https://${BH_DOMAIN}/docs"
echo "  Token   : see BH_API_TOKEN in ${ENV_FILE}"
echo "  Tunnel  : ssh -L 8080:127.0.0.1:8080 ${SSH_USER}@${SSH_HOST}"
