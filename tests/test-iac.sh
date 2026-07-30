#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_IMAGE="hashicorp/terraform@sha256:6bbb82d575aa7bd4f0a2c6e3a0838ab9590426c08a71d7a2783643f01004d356"
STEP_CA_IMAGE="smallstep/step-ca@sha256:a2b17872915c193259b75a5474c398326f41bd199f0842093e52cf4182bc8270"
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
  -ec 'tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work -xf -; cd /work/environments/dev/eu-central-1; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'mkdir -p /work/prod; tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work/prod -xf -; cd /work/prod/environments/prod/eu-central-1; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'mkdir -p /work/euw1; tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work/euw1 -xf -; cd /work/euw1/environments/prod/eu-west-1; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'mkdir -p /work/global; tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work/global -xf -; cd /work/global/environments/global/route53-failover; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'mkdir -p /work/gitlab-terraform-oidc-check; tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work/gitlab-terraform-oidc-check -xf -; cd /work/gitlab-terraform-oidc-check/tests/gitlab-terraform-oidc-check; terraform init -backend=false -input=false; terraform validate'

docker run --rm \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/sh \
  "${TERRAFORM_IMAGE}" \
  -ec 'mkdir -p /work/template-check; tar --exclude=.terraform --exclude=.git -C /source -cf - . | tar -C /work/template-check -xf -; cd /work/template-check/tests/template-check; terraform init -backend=false -input=false; terraform apply -auto-approve -refresh=false -input=false -lock=false >/dev/null; terraform output -raw runtime_compose >/work/rendered-step-ca-compose.yml; terraform output -raw runtime_ha_compose >/work/rendered-step-ca-ha-compose.yml; terraform output -raw gitlab_broker_compose >/work/rendered-gitlab-broker-compose.yml; terraform output -raw lean_runtime_bootstrap >/work/rendered-lean-runtime-bootstrap.sh; terraform output -raw ha_runtime_bootstrap >/work/rendered-ha-runtime-bootstrap.sh'

docker compose -f "${WORK_DIR}/rendered-step-ca-compose.yml" config --quiet
STEP_CA_DB_PASSWORD=local-validation-value docker compose -f "${WORK_DIR}/rendered-step-ca-ha-compose.yml" config --quiet
docker compose -f "${WORK_DIR}/rendered-gitlab-broker-compose.yml" config --quiet
docker run --rm -v "${WORK_DIR}:/work:ro" --entrypoint /bin/bash "${STEP_CA_IMAGE}" -n \
  /work/rendered-lean-runtime-bootstrap.sh /work/rendered-ha-runtime-bootstrap.sh

printf '%s\n' 'Terraform checks passed'
