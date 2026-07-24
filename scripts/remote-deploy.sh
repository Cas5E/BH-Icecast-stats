#!/usr/bin/env bash
# Deploy BH-Icecast to a remote Linux host over SSH.
# Usage:
#   export SSH_HOST=185.249.252.114 SSH_USER=root
#   export SSHPASS='...'   # or use SSH keys
#   bash scripts/remote-deploy.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_HOST="${SSH_HOST:?set SSH_HOST}"
SSH_USER="${SSH_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/opt/bh-icecast}"

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

echo "==> Ensuring remote Docker"
ssh_cmd "${SSH_USER}@${SSH_HOST}" bash -s <<'REMOTE'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker compose version >/dev/null
REMOTE

echo "==> Syncing project to ${REMOTE_DIR}"
ssh_cmd "${SSH_USER}@${SSH_HOST}" "mkdir -p '${REMOTE_DIR}'"

if command -v rsync >/dev/null 2>&1; then
  RSYNC_SSH="ssh -o StrictHostKeyChecking=accept-new"
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    RSYNC_SSH="sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no"
  fi
  rsync -az --delete \
    --exclude '.git' \
    --exclude '.venv' \
    --exclude 'api/.venv' \
    --exclude 'data' \
    --exclude 'api/data' \
    --exclude '__pycache__' \
    -e "$RSYNC_SSH" \
    "$ROOT/" "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/"
else
  tar czf /tmp/bh-icecast-deploy.tgz \
    --exclude .git --exclude .venv --exclude api/.venv \
    --exclude data --exclude api/data --exclude __pycache__ \
    -C "$ROOT" .
  scp_cmd /tmp/bh-icecast-deploy.tgz "${SSH_USER}@${SSH_HOST}:/tmp/bh-icecast-deploy.tgz"
  ssh_cmd "${SSH_USER}@${SSH_HOST}" "mkdir -p '${REMOTE_DIR}' && tar xzf /tmp/bh-icecast-deploy.tgz -C '${REMOTE_DIR}' && rm -f /tmp/bh-icecast-deploy.tgz"
fi

echo "==> Building and starting stack"
ssh_cmd "${SSH_USER}@${SSH_HOST}" bash -s <<REMOTE
set -euo pipefail
cd '${REMOTE_DIR}'
chmod +x scripts/*.sh nginx/docker-entrypoint.sh icecast/docker-entrypoint.sh
if [[ ! -f .env ]]; then
  echo "ERROR: .env missing on server. Upload it first."
  exit 1
fi
docker compose up -d --build
sleep 3
docker compose ps
REMOTE

echo "==> Requesting Let's Encrypt certificate"
ssh_cmd "${SSH_USER}@${SSH_HOST}" "cd '${REMOTE_DIR}' && bash scripts/init-ssl.sh"

echo "==> Done"
ssh_cmd "${SSH_USER}@${SSH_HOST}" "cd '${REMOTE_DIR}' && grep BH_API_TOKEN .env | sed 's/=.*/=***/'"
echo "Health: https://${BH_DOMAIN:-icecast.ebbersbroadcast.technology}/health"
