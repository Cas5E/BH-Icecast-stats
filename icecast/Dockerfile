FROM debian:bookworm-slim

# Prevent package postinst from trying to start services in the build
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        icecast2 \
        gettext-base \
        ca-certificates \
        media-types \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/sbin/policy-rc.d \
    && mkdir -p /var/log/icecast2 /etc/icecast2 \
    && (getent group icecast >/dev/null || groupadd -r icecast) \
    && (id -u icecast >/dev/null 2>&1 || useradd -r -g icecast -d /usr/share/icecast2 -s /usr/sbin/nologin icecast) \
    && chown -R icecast:icecast /var/log/icecast2 /usr/share/icecast2 \
    && chmod 755 /var/log/icecast2

COPY icecast.xml.template /etc/icecast2/icecast.xml.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/docker-entrypoint.sh"]
