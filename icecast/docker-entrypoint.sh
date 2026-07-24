#!/bin/sh
set -eu

: "${ICECAST_SOURCE_PASSWORD:?ICECAST_SOURCE_PASSWORD is required}"
: "${ICECAST_RELAY_PASSWORD:?ICECAST_RELAY_PASSWORD is required}"
: "${ICECAST_ADMIN_USER:=admin}"
: "${ICECAST_ADMIN_PASSWORD:?ICECAST_ADMIN_PASSWORD is required}"
: "${ICECAST_HOSTNAME:=localhost}"

export ICECAST_SOURCE_PASSWORD ICECAST_RELAY_PASSWORD
export ICECAST_ADMIN_USER ICECAST_ADMIN_PASSWORD ICECAST_HOSTNAME

envsubst < /etc/icecast2/icecast.xml.template > /etc/icecast2/icecast.xml
chown icecast:icecast /etc/icecast2/icecast.xml
chmod 640 /etc/icecast2/icecast.xml

# Start as root; Icecast drops to <changeowner> user from the config.
exec icecast2 -c /etc/icecast2/icecast.xml
