#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "${ROOT_DIR}/docker-compose.local.yml")
STEP_CA_IMAGE="smallstep/step-ca@sha256:a2b17872915c193259b75a5474c398326f41bd199f0842093e52cf4182bc8270"
PROJECT_NAME="pki-local-test"
STATE_VOLUME="${PROJECT_NAME}_step-ca-state"
BACKUP_VOLUME="pki-local-recovery-backup-${RANDOM}-${RANDOM}"
WORK_DIR="$(mktemp -d -t pki-local-recovery.XXXXXX)"

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

cleanup() {
  "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  docker volume rm "${BACKUP_VOLUME}" >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

issue_and_revoke() {
  "${COMPOSE[@]}" run --rm --use-aliases -T \
    -e CA_FINGERPRINT="${1}" \
    -v "${WORK_DIR}:/recovery" \
    step-cli \
    -ec '
      set -euo pipefail
      ca_url="https://step-ca:9000"
      password_file=/tmp/provisioner-password
      printf "%s\\n" "local-test-password-not-for-production" > "${password_file}"
      step ca bootstrap --ca-url "${ca_url}" --fingerprint "${CA_FINGERPRINT}" --install=false
      root="$(step path)/certs/root_ca.crt"
      step ca certificate recovery.pki.test /recovery/revoked.crt /recovery/revoked.key \
        --ca-url "${ca_url}" \
        --root "${root}" \
        --provisioner local-test \
        --provisioner-password-file "${password_file}"
      step ca revoke \
        --cert /recovery/revoked.crt \
        --key /recovery/revoked.key \
        --ca-url "${ca_url}" \
        --root "${root}"
    '
}

verify_restored_ca() {
  "${COMPOSE[@]}" run --rm --use-aliases -T \
    -e CA_FINGERPRINT="${1}" \
    -v "${WORK_DIR}:/recovery" \
    step-cli \
    -ec '
      set -euo pipefail
      ca_url="https://step-ca:9000"
      password_file=/tmp/provisioner-password
      printf "%s\\n" "local-test-password-not-for-production" > "${password_file}"
      step ca bootstrap --ca-url "${ca_url}" --fingerprint "${CA_FINGERPRINT}" --install=false
      root="$(step path)/certs/root_ca.crt"
      if step ca renew --force \
        --ca-url "${ca_url}" \
        --root "${root}" \
        /recovery/revoked.crt /recovery/revoked.key; then
        printf "%s\\n" "recovered CA accepted renewal of a certificate revoked before backup" >&2
        exit 1
      fi
      step ca certificate restored.pki.test /recovery/restored.crt /recovery/restored.key \
        --ca-url "${ca_url}" \
        --root "${root}" \
        --provisioner local-test \
        --provisioner-password-file "${password_file}"
      step certificate verify --roots "${root}" /recovery/restored.crt
    '
}

"${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE[@]}" up --detach --wait step-ca >/dev/null

original_fingerprint="$("${COMPOSE[@]}" exec -T step-ca step certificate fingerprint /home/step/certs/root_ca.crt)"
issue_and_revoke "${original_fingerprint}"

docker volume create "${BACKUP_VOLUME}" >/dev/null
docker run --rm \
  --user 0:0 \
  -v "${STATE_VOLUME}:/source:ro" \
  -v "${BACKUP_VOLUME}:/target" \
  --entrypoint /bin/bash \
  "${STEP_CA_IMAGE}" \
  -ec 'tar -C /source -cf - . | tar -C /target -xf -; test -f /target/config/ca.json; test -f /target/secrets/password'

# Simulate the loss of the original host state. The only state restored to the
# replacement volume is the snapshot, never the original named Docker volume.
"${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null
docker volume create \
  --label "com.docker.compose.project=${PROJECT_NAME}" \
  --label "com.docker.compose.volume=step-ca-state" \
  "${STATE_VOLUME}" >/dev/null
docker run --rm \
  --user 0:0 \
  -v "${BACKUP_VOLUME}:/source:ro" \
  -v "${STATE_VOLUME}:/target" \
  --entrypoint /bin/bash \
  "${STEP_CA_IMAGE}" \
  -ec 'tar -C /source -cf - . | tar -C /target -xf -; test -f /target/config/ca.json; test -f /target/secrets/password'

"${COMPOSE[@]}" up --detach --wait step-ca >/dev/null
restored_fingerprint="$("${COMPOSE[@]}" exec -T step-ca step certificate fingerprint /home/step/certs/root_ca.crt)"
[[ "${original_fingerprint}" == "${restored_fingerprint}" ]] || {
  printf '%s\n' 'recovered CA root fingerprint differs from the backed-up state' >&2
  exit 1
}
verify_restored_ca "${original_fingerprint}"

printf '%s\n' 'local CA recovery checks passed'
