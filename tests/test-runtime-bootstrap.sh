#!/bin/bash
set -euo pipefail

COMPOSE_VERSION="v5.3.1"
COMPOSE_SHA256="aa611e811d0ea25897839c404bfb5bf93ce706dc51c500a4457890f5d0606a86"
AMAZON_LINUX_IMAGE="amazonlinux@sha256:c4b0d324eaacbc5805ab5f147ba71963184752da90340bf0803c1034a170c8d1"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

docker run --rm \
  -e COMPOSE_VERSION="${COMPOSE_VERSION}" \
  -e COMPOSE_SHA256="${COMPOSE_SHA256}" \
  --entrypoint /bin/sh \
  "${AMAZON_LINUX_IMAGE}" \
  -ec '
    command -v curl >/dev/null
    dnf install -y docker gettext >/dev/null
    install -d -m 0755 /usr/local/lib/docker/cli-plugins
    curl --fail --silent --show-error --location \
      --output /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-aarch64"
    printf "%s  %s\n" "${COMPOSE_SHA256}" /usr/local/lib/docker/cli-plugins/docker-compose | sha256sum -c -
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
    docker compose version >/dev/null
    envsubst --version >/dev/null
  '

printf '%s\n' 'Amazon Linux Docker Compose bootstrap check passed'
