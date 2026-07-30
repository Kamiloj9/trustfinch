#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "${ROOT_DIR}/docker-compose.ha-local.yml")

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

cleanup() {
  "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
"${COMPOSE[@]}" up --detach --wait step-ca step-ca-secondary

fingerprint="$("${COMPOSE[@]}" exec -T step-ca step certificate fingerprint /home/step/certs/root_ca.crt)"

"${COMPOSE[@]}" run --rm -T \
  -e CA_FINGERPRINT="${fingerprint}" \
  step-cli \
  -ec '
    set -euo pipefail
    ca_url="https://step-ca:9000"
    password_file=/tmp/provisioner-password
    printf "%s\n" "local-test-password-not-for-production" > "${password_file}"

    step ca bootstrap --ca-url "${ca_url}" --fingerprint "${CA_FINGERPRINT}" --install=false
    root="$(step path)/certs/root_ca.crt"
    step ca certificate postgres.pki.test /tmp/primary.crt /tmp/primary.key \
      --ca-url "${ca_url}" \
      --root "${root}" \
      --provisioner local-test \
      --provisioner-password-file "${password_file}"
    step certificate verify --roots "${root}" /tmp/primary.crt

    step ca bootstrap --ca-url "https://step-ca-secondary:9000" --fingerprint "${CA_FINGERPRINT}" --install=false --force
    step ca certificate secondary.pki.test /tmp/secondary.crt /tmp/secondary.key \
      --ca-url "https://step-ca-secondary:9000" \
      --root "${root}" \
      --provisioner local-test \
      --provisioner-password-file "${password_file}"
    step certificate verify --roots "${root}" /tmp/secondary.crt

    if step ca certificate rejected.outside.test /tmp/rejected.crt /tmp/rejected.key \
      --ca-url "${ca_url}" \
      --root "${root}" \
      --provisioner local-test \
      --provisioner-password-file "${password_file}"; then
      printf "%s\n" "out-of-policy DNS SAN was unexpectedly issued" >&2
      exit 1
    fi
  '

printf '%s\n' 'local PostgreSQL-backed CA integration checks passed'
