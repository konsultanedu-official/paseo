FROM oven/bun:1.4.2-debian

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json ./
RUN bun install --production

COPY --chown=bun:bun src ./src

ENV HOME=/tmp
USER bun

CMD ["bun", "run", "src/server.ts"]
