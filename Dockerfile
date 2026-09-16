FROM ghcr.io/getpaseo/paseo:latest

USER root
RUN npm install -g opencode-ai \
    && chown -R paseo:paseo /home/paseo
