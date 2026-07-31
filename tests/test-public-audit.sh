#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLEAKS_IMAGE="zricethezav/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }
command -v git >/dev/null || { printf '%s\n' 'git is required' >&2; exit 1; }

docker run --rm \
  -v "${ROOT_DIR}:/repo:ro" \
  --entrypoint gitleaks \
  "${GITLEAKS_IMAGE}" \
  detect --source=/repo --no-git --no-banner

docker run --rm \
  -v "${ROOT_DIR}:/repo:ro" \
  --entrypoint gitleaks \
  "${GITLEAKS_IMAGE}" \
  detect --source=/repo --log-opts="--all" --no-banner

printf 'public source and Git-history audit passed\n'
