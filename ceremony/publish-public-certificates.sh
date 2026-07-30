#!/bin/bash
set -euo pipefail

# Uploads public certificates only. The ceremony output must have been inspected
# and approved before this command is used.
: "${ARTIFACT_BUCKET:?set ARTIFACT_BUCKET from Terraform output}"
: "${AWS_SHARED_CONFIG_DIR:?set an absolute directory containing AWS SSO/profile config}"

OUTPUT_DIR="${OUTPUT_DIR:-$PWD/ceremony/output}"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
AWS_CLI_IMAGE="amazon/aws-cli@sha256:211d32cc6c64665ff5bcd0d3df1b169bdc106388e9451cfc115466da1f3c6099"

for certificate in root_ca.crt intermediate_ca.crt; do
  [[ -f "${OUTPUT_DIR}/${certificate}" ]] || { printf '%s\n' "Missing ${OUTPUT_DIR}/${certificate}" >&2; exit 2; }
done

docker run --rm \
  -e AWS_REGION \
  -e AWS_DEFAULT_REGION="${AWS_REGION}" \
  -e AWS_PROFILE \
  -e AWS_SDK_LOAD_CONFIG=1 \
  -v "${AWS_SHARED_CONFIG_DIR}:/root/.aws:ro" \
  -v "${OUTPUT_DIR}:/out:ro" \
  "${AWS_CLI_IMAGE}" s3 cp /out/root_ca.crt "s3://${ARTIFACT_BUCKET}/runtime/certs/root_ca.crt" --only-show-errors

docker run --rm \
  -e AWS_REGION \
  -e AWS_DEFAULT_REGION="${AWS_REGION}" \
  -e AWS_PROFILE \
  -e AWS_SDK_LOAD_CONFIG=1 \
  -v "${AWS_SHARED_CONFIG_DIR}:/root/.aws:ro" \
  -v "${OUTPUT_DIR}:/out:ro" \
  "${AWS_CLI_IMAGE}" s3 cp /out/intermediate_ca.crt "s3://${ARTIFACT_BUCKET}/runtime/certs/intermediate_ca.crt" --only-show-errors

printf '%s\n' "Published public CA certificates to s3://${ARTIFACT_BUCKET}/runtime/certs/."
