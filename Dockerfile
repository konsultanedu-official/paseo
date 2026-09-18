FROM ghcr.io/getpaseo/paseo:latest

USER root

ENV NPM_CONFIG_CACHE=/home/paseo/.cache/npm

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh ripgrep; \
    rm -rf /var/lib/apt/lists/*; \
    NPM_CONFIG_CACHE=/tmp/npm-cache npm install -g opencode-ai bun@1.4.2; \
    rm -rf /tmp/npm-cache

COPY --chown=paseo:paseo opencode*.json /etc/opencode/
COPY paseo-runtime-entrypoint.sh /usr/local/bin/paseo-runtime-entrypoint

RUN chmod 0755 /usr/local/bin/paseo-runtime-entrypoint

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/paseo-runtime-entrypoint"]
