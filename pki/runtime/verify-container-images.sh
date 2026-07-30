#!/bin/bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: verify-container-images.sh --compose-file FILE --public-key PEM [--cosign-image IMAGE] [--network NETWORK] [--docker-config-dir DIR] [--allow-insecure-no-tlog]' >&2
  exit 2
}

compose_file=""
public_key=""
cosign_image="ghcr.io/sigstore/cosign/cosign@sha256:c77247c92f4dfea851c70555738226498393e34e2f9ca83cb959e51c230e4ad7"
network="host"
docker_config_dir="${DOCKER_CONFIG:-/root/.docker}"
allow_insecure_no_tlog=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-file)
      compose_file="${2:-}"
      shift 2
      ;;
    --public-key)
      public_key="${2:-}"
      shift 2
      ;;
    --cosign-image)
      cosign_image="${2:-}"
      shift 2
      ;;
    --network)
      network="${2:-}"
      shift 2
      ;;
    --docker-config-dir)
      docker_config_dir="${2:-}"
      shift 2
      ;;
    --allow-insecure-no-tlog)
      allow_insecure_no_tlog=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ -f "${compose_file}" && ! -L "${compose_file}" && -f "${public_key}" && ! -L "${public_key}" ]] || {
  printf '%s\n' 'compose file or signing public key is missing or is a symlink' >&2
  exit 1
}
[[ "${cosign_image}" =~ ^.+@sha256:[0-9a-f]{64}$ ]] || {
  printf '%s\n' 'cosign image must be digest-pinned' >&2
  exit 1
}
[[ "${network}" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
  printf '%s\n' 'docker network selector contains unsupported characters' >&2
  exit 1
}

image_list="$(mktemp)"
sorted_image_list="$(mktemp)"
trap 'rm -f "${image_list}" "${sorted_image_list}"' EXIT
docker compose -f "${compose_file}" config --images > "${image_list}" || {
  printf '%s\n' 'could not read runtime container images from the Compose file' >&2
  exit 1
}

sort -u "${image_list}" > "${sorted_image_list}" || {
  printf '%s\n' 'could not sort runtime container image references' >&2
  exit 1
}
images=()
while IFS= read -r image; do
  [[ -n "${image}" ]] && images+=("${image}")
done < "${sorted_image_list}"
(( ${#images[@]} > 0 )) || {
  printf '%s\n' 'runtime Compose file declares no container images' >&2
  exit 1
}

docker_config_mount=(--label pki.runtime-image-verifier=true)
if [[ -d "${docker_config_dir}" && ! -L "${docker_config_dir}" ]]; then
  docker_config_mount=(-e DOCKER_CONFIG=/docker-config -v "${docker_config_dir}:/docker-config:ro")
fi

for image in "${images[@]}"; do
  [[ "${image}" =~ ^.+@sha256:[0-9a-f]{64}$ ]] || {
    printf 'runtime image is not digest-pinned: %s\n' "${image}" >&2
    exit 1
  }

  if [[ "${allow_insecure_no_tlog}" == true ]]; then
    docker run --rm --network "${network}" \
      "${docker_config_mount[@]}" \
      -v "${public_key}:/trust/release-signing-public.pem:ro" \
      "${cosign_image}" verify --insecure-ignore-tlog \
      --key /trust/release-signing-public.pem "${image}" >/dev/null
    docker run --rm --network "${network}" \
      "${docker_config_mount[@]}" \
      -v "${public_key}:/trust/release-signing-public.pem:ro" \
      "${cosign_image}" verify-attestation --insecure-ignore-tlog \
      --type spdxjson --key /trust/release-signing-public.pem "${image}" >/dev/null
  else
    docker run --rm --network "${network}" \
      "${docker_config_mount[@]}" \
      -v "${public_key}:/trust/release-signing-public.pem:ro" \
      "${cosign_image}" verify --key /trust/release-signing-public.pem "${image}" >/dev/null
    docker run --rm --network "${network}" \
      "${docker_config_mount[@]}" \
      -v "${public_key}:/trust/release-signing-public.pem:ro" \
      "${cosign_image}" verify-attestation \
      --type spdxjson --key /trust/release-signing-public.pem "${image}" >/dev/null
  fi
done

printf 'verified Cosign signatures and SPDX attestations for %s runtime image(s)\n' "${#images[@]}"
