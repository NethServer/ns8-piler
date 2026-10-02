# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ubuntu:resolute-20260912
ARG PILER_VERSION=1.4.9
# On a version bump, the new sha256 of the amd64 .deb:
#   curl -fsSL "https://api.github.com/repos/jsuto/piler/releases/tags/piler-<version>" | jq -r '.assets[] | select(.name | test("_amd64\\.deb$")) | .digest' | sed 's/^sha256://'
ARG PILER_SHA256=e6f9e5e7bf307f024ea248352b93d5cad0925f0f998b2902e0e64ce0db51859a
ARG SUPERCRONIC_VERSION=v0.2.49
# No API digest for this one, download and hash it:
#   curl -fsSLo supercronic "https://github.com/aptible/supercronic/releases/download/<version>/supercronic-linux-amd64" && sha256sum supercronic
ARG SUPERCRONIC_SHA256=a53ae236602c7338aba3fbaff40bda6300eae3b9fedb8261eb06cfe3724430c1

FROM ${BASE_IMAGE} AS fetcher

ARG PILER_VERSION
ARG TARGETARCH
ARG PILER_SHA256
ARG SUPERCRONIC_VERSION
ARG SUPERCRONIC_SHA256

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /fetch

RUN [ "${TARGETARCH:-amd64}" = "amd64" ] || { echo "unsupported TARGETARCH=${TARGETARCH}, only amd64 is built" >&2; exit 1; }

# The .deb name embeds a build hash, so Renovate only has to bump PILER_VERSION.
RUN url=$(curl -fsSL "https://api.github.com/repos/jsuto/piler/releases/tags/piler-${PILER_VERSION}" \
             | grep -o "https://github.com/jsuto/piler/releases/download/[^\"]*_amd64\.deb" \
             | head -n1) && \
    curl -fsSLo piler.deb "$url" && \
    echo "${PILER_SHA256}  piler.deb" | sha256sum -c -

RUN curl -fsSLo supercronic \
      "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" && \
    echo "${SUPERCRONIC_SHA256}  supercronic" | sha256sum -c - && \
    chmod +x supercronic

FROM ${BASE_IMAGE} AS shim

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*

COPY config/syslog-to-stderr.c /tmp/syslog-to-stderr.c
RUN gcc -O2 -Wall -Wextra -fPIC -shared -o /syslog-to-stderr.so /tmp/syslog-to-stderr.c

FROM ${BASE_IMAGE} AS runtime

# Or the label below gets Ubuntu's own image.version.
ARG PILER_VERSION

LABEL org.opencontainers.image.source="https://github.com/NethServer/ns8-piler" \
      org.opencontainers.image.authors="Stephane de Labrusse <stephane.delabrusse@nethesis.it>" \
      org.opencontainers.image.title="piler mail archiving server" \
      org.opencontainers.image.description="Rootless piler (email archiver) image: nginx, php-fpm and supervisord, running against external mariadb, manticore and memcached containers" \
      org.opencontainers.image.version="${PILER_VERSION}" \
      org.opencontainers.image.vendor="NethServer"

ENV DEBIAN_FRONTEND="noninteractive" \
    PILER_USER="piler" \
    MYSQL_DATABASE="piler" \
    PILER_STOP_DRAIN="1" \
    PILER_STOP_DRAIN_TIMEOUT="300" \
    PILER_STOP_DRAIN_INTERVAL="2"

# hadolint ignore=DL3008
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
       openssl sysstat bsdextrautils catdoc unrtf poppler-utils tnef libtre5 ca-certificates \
       mariadb-client-core python3 python3-mysqldb libzip5 \
       curl nginx \
       php-cli php-cgi php-mysql php-fpm php-zip php-ldap php-gd php-curl php-xml php-memcached \
       supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=fetcher /fetch/piler.deb /tmp/piler.deb
COPY --from=fetcher /fetch/supercronic /usr/local/bin/supercronic
COPY --from=shim /syslog-to-stderr.so /usr/local/lib/syslog-to-stderr.so

# piler's postinst creates the user; a fixed uid keeps volume ownership stable.
RUN dpkg -i /tmp/piler.deb && \
    rm -f /tmp/piler.deb && \
    groupmod -g 1000 piler && \
    usermod -u 1000 -g 1000 -s /usr/sbin/nologin piler && \
    touch /etc/piler/MANTICORE && \
    ln -sf /etc/piler/piler-nginx.conf /etc/nginx/sites-enabled/piler-nginx.conf && \
    rm -f /etc/nginx/sites-enabled/default /etc/piler/piler.key /etc/piler/piler.pem /etc/piler/config-site.php && \
    mkdir -p /var/piler/run && \
    grep -v 'indexer' /usr/share/piler/piler.cron > /etc/piler.cron

# No root to drop from: pidfiles and sockets move from root-owned /run to
# /var/piler/run, logs go to stdout/stderr.
RUN sed -i -E \
      -e '/^\s*user\s+\S+;/d' \
      -e 's%^pid\s+/run/nginx\.pid;%pid /var/piler/run/nginx.pid;%' \
      /etc/nginx/nginx.conf && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    sed -i -E \
      -e 's%^pid\s*=.*%pid = /var/piler/run/php-fpm.pid%' \
      -e 's%^error_log\s*=.*%error_log = /dev/stderr%' \
      /etc/php/*/fpm/php-fpm.conf && \
    find /etc/php -name 'www.conf' -exec \
      sed -i -E \
        -e '/^(user|group)\s*=/d' \
        -e 's%^listen\s*=.*%listen = /var/piler/run/php-fpm.sock%' \
        -e 's/^listen\.owner\s*=.*/listen.owner = piler/' \
        -e 's/^listen\.group\s*=.*/listen.group = piler/' \
        {} \; && \
    sed -i -E 's%unix:/run/php/[^;]*\.sock%unix:/var/piler/run/php-fpm.sock%' \
      /etc/piler/piler-nginx.conf.dist && \
    sed -i -E '0,/^server \{/s//server {\n        listen 80 default_server;\n        listen [::]:80 default_server;/' \
      /etc/piler/piler-nginx.conf.dist && \
    ln -sf "$(ls /usr/sbin/php-fpm* | head -n1)" /usr/local/bin/php-fpm && \
    chown -R piler:piler /etc/piler /var/piler /var/log/nginx /var/lib/nginx && \
    # The entrypoint reads *.dist from this snapshot: /etc/piler is a volume and
    # would go stale. Taken after the sed fixes above.
    cp -R /etc/piler /tmp/piler-conf && \
    rm -f /etc/piler/*.dist

COPY entrypoint.sh /entrypoint.sh
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY config/exit-on-fatal-listener.py /etc/supervisor/exit-on-fatal-listener.py
COPY config/piler-run.sh /etc/supervisor/piler-run.sh
COPY config/imap-fetch.py /usr/local/bin/piler-imap-fetch
RUN chmod +x /entrypoint.sh /etc/supervisor/piler-run.sh /usr/local/bin/piler-imap-fetch && \
    chown -R piler:piler /tmp/piler-conf && \
    chown piler:piler /entrypoint.sh /etc/supervisor/supervisord.conf /etc/supervisor/exit-on-fatal-listener.py /etc/supervisor/piler-run.sh /usr/local/bin/piler-imap-fetch

# The spool, /var/piler/tmp, must survive a container recreation.
VOLUME ["/etc/piler", "/var/piler/store", "/var/piler/tmp"]

EXPOSE 25 80 443

# Probing the web UI alone would report healthy with mail intake dead.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://localhost/ >/dev/null && curl -fsS --max-time 3 smtp://localhost:25/ >/dev/null || exit 1

USER piler

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
