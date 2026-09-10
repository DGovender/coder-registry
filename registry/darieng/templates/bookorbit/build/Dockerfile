FROM mcr.microsoft.com/devcontainers/javascript-node:24-bookworm

RUN apt-get update \
 && apt-get install --yes --no-install-recommends postgresql-client \
 && npm install --global pnpm@11.22.0 \
 && rm -rf /var/lib/apt/lists/*

COPY bookorbit-db-reset /usr/local/bin/bookorbit-db-reset
