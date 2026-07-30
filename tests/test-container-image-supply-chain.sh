#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:c77247c92f4dfea851c70555738226498393e34e2f9ca83cb959e51c230e4ad7"
REGISTRY_IMAGE="registry@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373"
WORK_DIR="$(mktemp -d -t pki-container-image-supply-chain.XXXXXX)"
REGISTRY_NAME="pki-supply-chain-${RANDOM}-${RANDOM}"
REGISTRY_ID=""

cleanup() {
  if [[ -n "${REGISTRY_ID}" ]]; then
    docker stop "${REGISTRY_ID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

REGISTRY_ID="$(docker run -d --rm --name "${REGISTRY_NAME}" -P "${REGISTRY_IMAGE}")"
registry_port="$(docker port "${REGISTRY_ID}" 5000/tcp | sed -E 's/.*:([0-9]+)$/\1/')"
for _ in $(seq 1 30); do
  curl --fail --silent "http://127.0.0.1:${registry_port}/v2/" >/dev/null && break
  sleep 1
done
curl --fail --silent "http://127.0.0.1:${registry_port}/v2/" >/dev/null

build_image() {
  local tag="$1"
  local label="${2:-}"
  local host_image="127.0.0.1:${registry_port}/pki-fixture:${tag}"
  if [[ -n "${label}" ]]; then
    docker build --quiet --tag "${host_image}" --label "${label}" \
      --file "${ROOT_DIR}/tests/fixtures/supply-chain.Dockerfile" "${ROOT_DIR}" >/dev/null
  else
    docker build --quiet --tag "${host_image}" \
      --file "${ROOT_DIR}/tests/fixtures/supply-chain.Dockerfile" "${ROOT_DIR}" >/dev/null
  fi
  docker push "${host_image}" >/dev/null
  docker image inspect --format "{{index .RepoDigests 0}}" "${host_image}"
}

signed_host_ref="$(build_image signed)"
signed_ref="localhost:5000/pki-fixture@${signed_host_ref##*@}"
platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "127.0.0.1:${registry_port}/pki-fixture:signed")"

COSIGN_PASSWORD=local-test-password docker run --rm \
  --network "container:${REGISTRY_ID}" \
  -e COSIGN_PASSWORD \
  -v "${WORK_DIR}:/work" \
  "${COSIGN_IMAGE}" generate-key-pair --output-key-prefix /work/cosign >/dev/null

COSIGN_PASSWORD=local-test-password "${ROOT_DIR}/ceremony/sign-container-image.sh" \
  --image "${signed_ref}" \
  --key "${WORK_DIR}/cosign.key" \
  --platform "${platform}" \
  --sbom-output "${WORK_DIR}/signed.spdx.json" \
  --scan-output "${WORK_DIR}/signed.trivy.json" \
  --network "container:${REGISTRY_ID}" \
  --scanners secret \
  --tlog-upload false >/dev/null

rg --quiet 'SPDXID' "${WORK_DIR}/signed.spdx.json"
rg --quiet 'ArtifactName' "${WORK_DIR}/signed.trivy.json"
printf 'services:\n  fixture:\n    image: %s\n' "${signed_ref}" > "${WORK_DIR}/signed-compose.yml"
"${ROOT_DIR}/pki/runtime/verify-container-images.sh" \
  --compose-file "${WORK_DIR}/signed-compose.yml" \
  --public-key "${WORK_DIR}/cosign.pub" \
  --network "container:${REGISTRY_ID}" \
  --allow-insecure-no-tlog >/dev/null

unsigned_host_ref="$(build_image unsigned 'pki.fixture=unsigned')"
unsigned_ref="localhost:5000/pki-fixture@${unsigned_host_ref##*@}"
printf 'services:\n  fixture:\n    image: %s\n' "${unsigned_ref}" > "${WORK_DIR}/unsigned-compose.yml"
if "${ROOT_DIR}/pki/runtime/verify-container-images.sh" \
  --compose-file "${WORK_DIR}/unsigned-compose.yml" \
  --public-key "${WORK_DIR}/cosign.pub" \
  --network "container:${REGISTRY_ID}" \
  --allow-insecure-no-tlog; then
  printf '%s\n' 'unsigned container image was accepted' >&2
  exit 1
fi

printf '%s\n' 'container image supply-chain checks passed'
