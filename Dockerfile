FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g opencode-ai \
    && chown -R paseo:paseo /home/paseo

COPY --chown=paseo:paseo opencode.json /etc/opencode/opencode.json
