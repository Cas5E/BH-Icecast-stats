#!/bin/sh
set -eu

: "${ICECAST_SOURCE_PASSWORD:?ICECAST_SOURCE_PASSWORD is required}"
: "${ICECAST_RELAY_PASSWORD:?ICECAST_RELAY_PASSWORD is required}"
: "${ICECAST_ADMIN_USER:=admin}"
: "${ICECAST_ADMIN_PASSWORD:?ICECAST_ADMIN_PASSWORD is required}"
: "${ICECAST_HOSTNAME:=localhost}"

export ICECAST_SOURCE_PASSWORD ICECAST_RELAY_PASSWORD
export ICECAST_ADMIN_USER ICECAST_ADMIN_PASSWORD ICECAST_HOSTNAME

SHARED="${BH_ICECAST_SHARED:-/shared}"
mkdir -p "$SHARED"
MOUNTS_FILE="$SHARED/mounts.xml"
RELOAD_FLAG="$SHARED/reload"
CONFIG_OUT=/etc/icecast2/icecast.xml

build_config() {
  envsubst < /etc/icecast2/icecast.xml.template > /tmp/icecast.base.xml
  if [ -f "$MOUNTS_FILE" ]; then
    # Insert generated <mount> blocks before </icecast>
    awk -v mounts="$MOUNTS_FILE" '
      /<\/icecast>/ {
        while ((getline line < mounts) > 0) print line
        close(mounts)
      }
      { print }
    ' /tmp/icecast.base.xml > "$CONFIG_OUT"
  else
    cp /tmp/icecast.base.xml "$CONFIG_OUT"
  fi
  chown icecast:icecast "$CONFIG_OUT"
  chmod 640 "$CONFIG_OUT"
}

build_config

# Run Icecast in background so we can SIGHUP on mount changes
icecast2 -c "$CONFIG_OUT" &
ICE_PID=$!

echo "Icecast started pid=$ICE_PID (direct source port 8000)"

# Wait until process is up
sleep 1
if ! kill -0 "$ICE_PID" 2>/dev/null; then
  echo "Icecast failed to start" >&2
  wait "$ICE_PID" || true
  exit 1
fi

trap 'kill -TERM "$ICE_PID" 2>/dev/null || true; exit 0' TERM INT

LAST_MTIME=""
while kill -0 "$ICE_PID" 2>/dev/null; do
  NEED=0
  if [ -f "$RELOAD_FLAG" ]; then
    NEED=1
    rm -f "$RELOAD_FLAG"
  fi
  if [ -f "$MOUNTS_FILE" ]; then
    MTIME=$(stat -c %Y "$MOUNTS_FILE" 2>/dev/null || echo 0)
    if [ "$MTIME" != "$LAST_MTIME" ]; then
      NEED=1
      LAST_MTIME="$MTIME"
    fi
  fi
  if [ "$NEED" -eq 1 ]; then
    echo "Reloading Icecast config (SIGHUP)…"
    build_config
    kill -HUP "$ICE_PID" || true
  fi
  sleep 1
done

wait "$ICE_PID" || true
