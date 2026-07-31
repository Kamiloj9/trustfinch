#!/bin/bash
set -euo pipefail

COMPOSE_VERSION="v5.3.1"
AMAZON_LINUX_IMAGE="amazonlinux@sha256:c4b0d324eaacbc5805ab5f147ba71963184752da90340bf0803c1034a170c8d1"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

case "$(uname -m)" in
  arm64|aarch64)
    COMPOSE_ARCH="aarch64"
    COMPOSE_SHA256="aa611e811d0ea25897839c404bfb5bf93ce706dc51c500a4457890f5d0606a86"
    ;;
  x86_64)
    COMPOSE_ARCH="x86_64"
    COMPOSE_SHA256="f9ebc6ebdb19d769b793c245a736caaeb198c62587f13b25c660c13b4987f959"
    ;;
  *)
    printf 'unsupported Docker Compose test architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

docker run --rm \
  -e COMPOSE_ARCH="${COMPOSE_ARCH}" \
  -e COMPOSE_VERSION="${COMPOSE_VERSION}" \
  -e COMPOSE_SHA256="${COMPOSE_SHA256}" \
  --entrypoint /bin/sh \
  "${AMAZON_LINUX_IMAGE}" \
  -ec '
    command -v curl >/dev/null
    dnf install -y docker gettext amazon-cloudwatch-agent >/dev/null 2>&1
    rpm -q amazon-cloudwatch-agent >/dev/null
    install -d -m 0755 /usr/local/lib/docker/cli-plugins
    curl --fail --silent --show-error --location \
      --output /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"
    printf "%s  %s\n" "${COMPOSE_SHA256}" /usr/local/lib/docker/cli-plugins/docker-compose | sha256sum -c -
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
    docker compose version >/dev/null
    envsubst --version >/dev/null
  '

printf '%s\n' 'Amazon Linux Docker Compose bootstrap check passed'
