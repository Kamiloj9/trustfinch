#!/bin/bash
set -euo pipefail

COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:c77247c92f4dfea851c70555738226498393e34e2f9ca83cb959e51c230e4ad7"
SYFT_IMAGE="anchore/syft@sha256:c15fa8af4c25edd72c0daf026d095fe51adbcfc7ad5d79a66e93d88f249e5abb"
TRIVY_IMAGE="aquasec/trivy@sha256:cffe3f5161a47a6823fbd23d985795b3ed72a4c806da4c4df16266c02accdd6f"

usage() {
  printf '%s\n' 'usage: sign-container-image.sh --image IMAGE@sha256:DIGEST --key COSIGN_KEY_OR_AWS_KMS_URI --platform linux/ARCH --sbom-output FILE --scan-output FILE [--network NETWORK] [--docker-config-dir DIR] [--aws-config-dir DIR] [--scanners LIST] [--tlog-upload true|false]' >&2
  exit 2
}

image=""
key=""
platform=""
sbom_output=""
scan_output=""
network="host"
docker_config_dir=""
aws_config_dir=""
scanners="vuln,secret"
tlog_upload=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      image="${2:-}"
      shift 2
      ;;
    --key)
      key="${2:-}"
      shift 2
      ;;
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --sbom-output)
      sbom_output="${2:-}"
      shift 2
      ;;
    --scan-output)
      scan_output="${2:-}"
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
    --aws-config-dir)
      aws_config_dir="${2:-}"
      shift 2
      ;;
    --scanners)
      scanners="${2:-}"
      shift 2
      ;;
    --tlog-upload)
      tlog_upload="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "${image}" =~ ^.+@sha256:[0-9a-f]{64}$ ]] || {
  printf '%s\n' 'image must be referenced by an immutable sha256 digest' >&2
  exit 2
}
[[ -n "${key}" && "${platform}" =~ ^linux/[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || usage
[[ -n "${sbom_output}" && -n "${scan_output}" ]] || usage
[[ "${network}" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
  printf '%s\n' 'docker network selector contains unsupported characters' >&2
  exit 2
}
[[ "${scanners}" =~ ^(vuln|secret)(,(vuln|secret))*$ ]] || {
  printf '%s\n' 'scanners must be a comma-separated subset of vuln,secret' >&2
  exit 2
}
[[ "${tlog_upload}" == true || "${tlog_upload}" == false ]] || usage

sbom_dir="$(cd "$(dirname "${sbom_output}")" && pwd)"
scan_dir="$(cd "$(dirname "${scan_output}")" && pwd)"
sbom_file="$(basename "${sbom_output}")"
scan_file="$(basename "${scan_output}")"

key_mount=(--label pki.release-image-signer=true)
cosign_key="${key}"
if [[ "${key}" != *"://"* ]]; then
  [[ -f "${key}" && ! -L "${key}" ]] || {
    printf '%s\n' 'local Cosign key file is missing or is a symlink' >&2
    exit 1
  }
  key_dir="$(cd "$(dirname "${key}")" && pwd)"
  key_mount=(-v "${key_dir}:/signing-key:ro")
  cosign_key="/signing-key/$(basename "${key}")"
fi

password_env=(--label pki.release-image-signer=true)
if [[ -n "${COSIGN_PASSWORD:-}" ]]; then
  password_env=(-e COSIGN_PASSWORD)
fi

docker_config_mount=(--label pki.release-image-signer=true)
if [[ -d "${docker_config_dir}" && ! -L "${docker_config_dir}" ]]; then
  docker_config_mount=(-e DOCKER_CONFIG=/docker-config -v "${docker_config_dir}:/docker-config:ro")
fi

aws_credential_env=(--label pki.release-image-signer=true)
for aws_variable in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_EC2_METADATA_DISABLED; do
  if [[ -n "${!aws_variable:-}" ]]; then
    aws_credential_env+=(-e "${aws_variable}")
  fi
done

aws_config_mount=(--label pki.release-image-signer=true)
if [[ -n "${aws_config_dir}" ]]; then
  [[ -d "${aws_config_dir}" && ! -L "${aws_config_dir}" ]] || {
    printf '%s\n' 'AWS configuration directory is missing or is a symlink' >&2
    exit 1
  }
  aws_config_mount=(-e AWS_CONFIG_FILE=/root/.aws/config -e AWS_SHARED_CREDENTIALS_FILE=/root/.aws/credentials -v "${aws_config_dir}:/root/.aws:ro")
fi

docker run --rm --network "${network}" \
  -v "${sbom_dir}:/output" \
  "${SYFT_IMAGE}" "${image}" -o "spdx-json=/output/${sbom_file}"
docker run --rm --network "${network}" \
  -v "${scan_dir}:/output" \
  "${TRIVY_IMAGE}" image --platform "${platform}" --scanners "${scanners}" \
  --severity HIGH,CRITICAL --exit-code 1 --format json --output "/output/${scan_file}" "${image}"

tlog_option=(--tlog-upload="${tlog_upload}")
docker run --rm --network "${network}" "${password_env[@]}" "${key_mount[@]}" \
  "${docker_config_mount[@]}" "${aws_credential_env[@]}" "${aws_config_mount[@]}" \
  "${COSIGN_IMAGE}" sign --yes "${tlog_option[@]}" --key "${cosign_key}" "${image}"
docker run --rm --network "${network}" "${password_env[@]}" "${key_mount[@]}" \
  "${docker_config_mount[@]}" "${aws_credential_env[@]}" "${aws_config_mount[@]}" \
  -v "${sbom_dir}:/output:ro" \
  "${COSIGN_IMAGE}" attest --yes "${tlog_option[@]}" --type spdxjson \
  --predicate "/output/${sbom_file}" --key "${cosign_key}" "${image}"

printf 'scanned, generated SPDX SBOM, signed, and attested %s\n' "${image}"
