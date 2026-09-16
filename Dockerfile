FROM ghcr.io/getpaseo/paseo:latest

USER root

ENV NPM_CONFIG_CACHE=/home/paseo/.cache/npm

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p "$NPM_CONFIG_CACHE"; \
    npm install -g opencode-ai; \
    chown -R paseo:paseo /home/paseo

COPY --chown=paseo:paseo opencode.json /etc/opencode/opencode.json
