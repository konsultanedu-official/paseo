FROM ghcr.io/getpaseo/paseo:latest

ARG TARGETARCH
ARG GITLEAKS_VERSION=8.30.1

USER root

ENV NPM_CONFIG_CACHE=/home/paseo/.cache/npm

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh ripgrep curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    case "$TARGETARCH" in \
      amd64) GITLEAKS_ARCH=x64 ;; \
      arm64) GITLEAKS_ARCH=arm64 ;; \
      *) echo "Unsupported architecture for gitleaks: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" -o /tmp/gitleaks.tar.gz; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" -o /tmp/gitleaks-checksums.txt; \
    cd /tmp; \
    grep "gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" gitleaks-checksums.txt | sha256sum -c -; \
    tar -xzf gitleaks.tar.gz -C /usr/local/bin gitleaks; \
    chmod 0755 /usr/local/bin/gitleaks; \
    gitleaks version; \
    rm -f /tmp/gitleaks.tar.gz /tmp/gitleaks-checksums.txt; \
    NPM_CONFIG_CACHE=/tmp/npm-cache npm install -g opencode-ai bun@1.4.2; \
    rm -rf /tmp/npm-cache

COPY --chown=paseo:paseo opencode*.json /etc/opencode/
COPY --chown=paseo:paseo skills/ /usr/local/share/paseo-skills/
COPY paseo-runtime-entrypoint.sh /usr/local/bin/paseo-runtime-entrypoint

RUN chmod 0755 /usr/local/bin/paseo-runtime-entrypoint

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/paseo-runtime-entrypoint"]
