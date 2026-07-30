#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_IMAGE="golang@sha256:2d40d4fc278dad38be0777d5e2a88a2c6dee51b0b29c97a764fc6c6a11ca893c"
IMAGE_ID_FILE="$(mktemp -t pki-gitlab-broker-image.XXXXXX)"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

cleanup() {
  if [[ -s "${IMAGE_ID_FILE}" ]]; then
    docker image rm --force "$(<"${IMAGE_ID_FILE}")" >/dev/null 2>&1 || true
  fi
  rm -f "${IMAGE_ID_FILE}"
}
trap cleanup EXIT

docker build --quiet --iidfile "${IMAGE_ID_FILE}" --file "${ROOT_DIR}/broker/Dockerfile" "${ROOT_DIR}/broker" >/dev/null

docker run --rm \
  -v "${ROOT_DIR}:/workspace:ro" \
  -w /workspace/broker \
  "${GO_IMAGE}" \
  go test ./...

printf '%s\n' 'GitLab enrollment broker checks passed'
