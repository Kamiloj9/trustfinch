#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "${ROOT_DIR}/docker-compose.local.yml")
CONFIG_DIR="$(mktemp -d -t pki-caddy.XXXXXX)"
CADDY_IMAGE="caddy@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

cleanup() {
  "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "${CONFIG_DIR}"
}
trap cleanup EXIT

"${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE[@]}" up --detach --wait step-ca

fingerprint="$("${COMPOSE[@]}" exec -T step-ca step certificate fingerprint /home/step/certs/root_ca.crt)"

# Validate the exact pinned Caddy image and the rendered Caddyfile against a
# real local CA root. This is parsing validation only; no public ACME request
# is made in the local test.
mkdir -p "${CONFIG_DIR}/step-ca"
"${COMPOSE[@]}" cp step-ca:/home/step/certs/root_ca.crt "${CONFIG_DIR}/step-ca/root_ca.crt"
sed 's/\${ca_fqdn}/ca.pki.test/g' "${ROOT_DIR}/pki/config/Caddyfile.tftpl" > "${CONFIG_DIR}/Caddyfile"
docker run --rm \
  --entrypoint caddy \
  -v "${CONFIG_DIR}:/etc/caddy:ro" \
  "${CADDY_IMAGE}" validate --config /etc/caddy/Caddyfile --adapter caddyfile

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

    step ca certificate service.pki.test /tmp/allowed.crt /tmp/allowed.key \
      --ca-url "${ca_url}" \
      --root "${root}" \
      --provisioner local-test \
      --provisioner-password-file "${password_file}"
    step certificate verify --roots "${root}" /tmp/allowed.crt

    if step ca certificate rejected.outside.test /tmp/rejected.crt /tmp/rejected.key \
      --ca-url "${ca_url}" \
      --root "${root}" \
      --provisioner local-test \
      --provisioner-password-file "${password_file}"; then
      printf "%s\n" "out-of-policy DNS SAN was unexpectedly issued" >&2
      exit 1
    fi
  '

printf '%s\n' 'local CA policy and issuance integration checks passed'
