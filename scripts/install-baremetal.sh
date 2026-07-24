#!/usr/bin/env bash
#
# Bare-metal installer for Debian/Ubuntu.
# Installs Icecast2, Nginx, Python API + systemd units.
# No Icecast reload on mount changes — auth goes through Nginx + API.
#
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_USER="bh-icecast"
APP_DIR="/opt/bh-icecast"
DATA_DIR="/var/lib/bh-icecast"
ENV_FILE="/etc/bh-icecast.env"

echo "==> Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  icecast2 nginx python3 python3-venv python3-pip curl openssl gettext-base rsync

echo "==> Creating user and directories"
id -u "$APP_USER" &>/dev/null || useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR" "$DATA_DIR" /var/log/bh-icecast
rsync -a --delete \
  --exclude '.git' \
  --exclude '.env' \
  --exclude 'api/data' \
  --exclude '__pycache__' \
  --exclude 'api/.venv' \
  "$ROOT/" "$APP_DIR/"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "==> Writing $ENV_FILE"
  MASTER="$(openssl rand -hex 24)"
  RELAY="$(openssl rand -hex 24)"
  ADMIN="$(openssl rand -hex 24)"
  TOKEN="$(openssl rand -hex 24)"
  cat > "$ENV_FILE" <<EOF
ICECAST_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
ICECAST_SOURCE_PASSWORD=$MASTER
ICECAST_RELAY_PASSWORD=$RELAY
ICECAST_ADMIN_USER=admin
ICECAST_ADMIN_PASSWORD=$ADMIN
ICECAST_ADMIN_URL=http://127.0.0.1:8001
BH_PUBLIC_LISTEN_BASE=http://$(hostname -f 2>/dev/null || hostname):8000
BH_API_TOKEN=$TOKEN
BH_DATABASE_URL=sqlite:////var/lib/bh-icecast/bh-icecast.db
BH_DATA_DIR=/var/lib/bh-icecast
EOF
  chmod 600 "$ENV_FILE"
  echo "API token stored in $ENV_FILE (BH_API_TOKEN)"
else
  echo "==> Keeping existing $ENV_FILE"
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  MASTER="${ICECAST_SOURCE_PASSWORD:?missing ICECAST_SOURCE_PASSWORD in $ENV_FILE}"
fi

echo "==> Rendering Icecast config"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
envsubst < "$APP_DIR/icecast/icecast.xml.template" > /etc/icecast2/icecast.xml
# Debian package expects this
sed -i 's/ENABLE=false/ENABLE=true/' /etc/default/icecast2 2>/dev/null || true
chown icecast:icecast /etc/icecast2/icecast.xml || true

echo "==> Python venv + API deps"
python3 -m venv "$APP_DIR/api/.venv"
"$APP_DIR/api/.venv/bin/pip" install --upgrade pip
"$APP_DIR/api/.venv/bin/pip" install -r "$APP_DIR/api/requirements.txt"
chown -R "$APP_USER:$APP_USER" "$DATA_DIR" "$APP_DIR/api"

echo "==> Systemd unit: bh-icecast-api"
cat > /etc/systemd/system/bh-icecast-api.service <<EOF
[Unit]
Description=BH-Icecast management API
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
EnvironmentFile=$ENV_FILE
WorkingDirectory=$APP_DIR/api
ExecStart=$APP_DIR/api/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8081
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "==> Nginx stream/auth proxy"
BASIC="$(printf 'source:%s' "$ICECAST_SOURCE_PASSWORD" | base64 -w0 2>/dev/null || printf 'source:%s' "$ICECAST_SOURCE_PASSWORD" | base64)"
cat > /etc/nginx/sites-available/bh-icecast <<EOF
# BH-Icecast — public stream port + API
upstream bh_icecast { server 127.0.0.1:8001; }
upstream bh_api { server 127.0.0.1:8081; }

server {
    listen 8000;
    server_name _;

    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 7d;
    proxy_send_timeout 7d;

    location ^~ /admin { return 403; }

    location = /_bh_source_auth {
        internal;
        proxy_pass http://bh_api/internal/source-auth;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header X-Original-URI \$request_uri;
        proxy_set_header X-Original-Method \$request_method;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location / {
        limit_except GET HEAD {
            auth_request /_bh_source_auth;
            proxy_set_header Authorization "Basic $BASIC";
        }
        proxy_pass http://bh_icecast;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Connection "";
    }
}

server {
    listen 8080;
    server_name _;
    location / {
        proxy_pass http://bh_api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sfn /etc/nginx/sites-available/bh-icecast /etc/nginx/sites-enabled/bh-icecast
rm -f /etc/nginx/sites-enabled/default

# Point Icecast at internal port 8001 so nginx owns :8000
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
export ICECAST_HOSTNAME ICECAST_SOURCE_PASSWORD ICECAST_RELAY_PASSWORD
export ICECAST_ADMIN_USER ICECAST_ADMIN_PASSWORD
# Override listen port in rendered config
python3 - <<'PY'
from pathlib import Path
p = Path("/etc/icecast2/icecast.xml")
text = p.read_text()
text = text.replace("<port>8000</port>", "<port>8001</port>")
text = text.replace("<bind-address>0.0.0.0</bind-address>", "<bind-address>127.0.0.1</bind-address>")
p.write_text(text)
print("Icecast bound to 127.0.0.1:8001")
PY

echo "==> Enabling services"
systemctl daemon-reload
systemctl enable --now icecast2
systemctl enable --now bh-icecast-api
nginx -t
systemctl reload nginx

echo
echo "BH-Icecast bare-metal install complete."
echo "  Streams : http://<host>:8000/<mount>"
echo "  API     : http://<host>:8080"
echo "  Token   : see BH_API_TOKEN in $ENV_FILE"
echo
echo "Example:"
echo "  curl -H \"Authorization: Bearer \$(grep BH_API_TOKEN $ENV_FILE | cut -d= -f2)\" \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"name\":\"live\"}' \\"
echo "    http://127.0.0.1:8080/api/v1/mounts"
