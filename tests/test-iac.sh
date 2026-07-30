#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_IMAGE="hashicorp/terraform@sha256:6bbb82d575aa7bd4f0a2c6e3a0838ab9590426c08a71d7a2783643f01004d356"
WORK_DIR="$(mktemp -d -t pki-terraform.XXXXXX)"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

command -v docker >/dev/null || { printf '%s\n' 'docker is required' >&2; exit 1; }

docker run --rm -v "${ROOT_DIR}:/workspace:ro" -w /workspace "${TERRAFORM_IMAGE}" fmt -check -recursive

# Provider installation and .terraform state happen in a temporary copy. The
# source tree remains read-only and no AWS credentials are passed to Docker.
docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'cp -a /source/. /work/; cd /work/environments/dev/eu-central-1; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'cp -a /source/. /work/template-check; cd /work/template-check/tests/template-check; terraform init -backend=false -input=false; terraform apply -auto-approve -refresh=false -input=false -lock=false >/dev/null; terraform output -raw runtime_compose >/work/rendered-step-ca-compose.yml'

docker compose -f "${WORK_DIR}/rendered-step-ca-compose.yml" config --quiet

printf '%s\n' 'Terraform checks passed'
