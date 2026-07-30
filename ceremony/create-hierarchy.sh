#!/bin/bash
set -euo pipefail

# Creates certificates only. The Root and Intermediate private keys must already
# exist in AWS KMS (created by Terraform) and never pass through this script.
: "${ROOT_KEY_ID:?set ROOT_KEY_ID from Terraform output}"
: "${INTERMEDIATE_KEY_ID:?set INTERMEDIATE_KEY_ID from Terraform output}"
: "${AWS_SHARED_CONFIG_DIR:?set an absolute directory containing AWS SSO/profile config}"

PKI_NAME="${PKI_NAME:-Example Company}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/ceremony/output}"
AWS_PROFILE="${AWS_PROFILE:-default}"
ROOT_AWS_REGION="${ROOT_AWS_REGION:-${AWS_REGION:-}}"
INTERMEDIATE_AWS_REGION="${INTERMEDIATE_AWS_REGION:-${AWS_REGION:-}}"
KMS_IMAGE="smallstep/step-kms-plugin@sha256:ea19a6e4f70cc6eee5bdadf20c09fc1b68f6d4491df7b91ab9a39a4898d5b28d"

if [[ -z "${ROOT_AWS_REGION}" || -z "${INTERMEDIATE_AWS_REGION}" ]]; then
  printf '%s\n' 'Set AWS_REGION for a single-region ceremony, or set ROOT_AWS_REGION and INTERMEDIATE_AWS_REGION.' >&2
  exit 2
fi

if [[ ! -d "${AWS_SHARED_CONFIG_DIR}" ]]; then
  printf '%s\n' "AWS_SHARED_CONFIG_DIR is not a directory: ${AWS_SHARED_CONFIG_DIR}" >&2
  exit 2
fi

if [[ -e "${OUTPUT_DIR}/intermediate_ca.crt" ]]; then
  printf '%s\n' "Refusing to overwrite existing intermediate certificate in ${OUTPUT_DIR}" >&2
  exit 2
fi

mkdir -p "${OUTPUT_DIR}"
ROOT_CERT_PATH="${ROOT_CERT_PATH:-${OUTPUT_DIR}/root_ca.crt}"

if [[ "${ROOT_CERT_PATH}" != "${OUTPUT_DIR}/root_ca.crt" && -f "${ROOT_CERT_PATH}" ]]; then
  install -m 0644 "${ROOT_CERT_PATH}" "${OUTPUT_DIR}/root_ca.crt"
  ROOT_CERT_PATH="${OUTPUT_DIR}/root_ca.crt"
fi

run_step() {
  docker run --rm \
    -e AWS_REGION="${ROOT_AWS_REGION}" \
    -e AWS_DEFAULT_REGION="${ROOT_AWS_REGION}" \
    -e AWS_PROFILE \
    -e AWS_SDK_LOAD_CONFIG=1 \
    -v "${AWS_SHARED_CONFIG_DIR}:/home/step/.aws:ro" \
    -v "${OUTPUT_DIR}:/out" \
    "${KMS_IMAGE}" "$@"
}

if [[ ! -f "${ROOT_CERT_PATH}" ]]; then
  if [[ "${ROOT_CERT_PATH}" != "${OUTPUT_DIR}/root_ca.crt" || -e "${ROOT_CERT_PATH}" ]]; then
    printf '%s\n' "Root certificate not found: ${ROOT_CERT_PATH}" >&2
    exit 2
  fi

  run_step step certificate create \
    --profile root-ca \
    --kms "awskms:region=${ROOT_AWS_REGION}" \
    --key "awskms:key-id=${ROOT_KEY_ID}" \
    --not-after 87600h \
    "${PKI_NAME} Root CA" /out/root_ca.crt
fi

run_step step certificate create \
  --profile intermediate-ca \
  --kms "awskms:region=${INTERMEDIATE_AWS_REGION}" \
  --ca-kms "awskms:region=${ROOT_AWS_REGION}" \
  --ca /out/root_ca.crt \
  --ca-key "awskms:key-id=${ROOT_KEY_ID}" \
  --key "awskms:key-id=${INTERMEDIATE_KEY_ID}" \
  --not-after 17520h \
  "${PKI_NAME} Intermediate CA" /out/intermediate_ca.crt

run_step step certificate inspect --format json /out/root_ca.crt >/dev/null
run_step step certificate inspect --format json /out/intermediate_ca.crt >/dev/null

printf '%s\n' "Created public certificates in ${OUTPUT_DIR}." \
  'Review and publish only these .crt files, then immediately apply Terraform with root_key_enabled=false.'
