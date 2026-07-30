#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEP_CA_IMAGE="smallstep/step-ca@sha256:a2b17872915c193259b75a5474c398326f41bd199f0842093e52cf4182bc8270"

cd "${ROOT_DIR}"

fail() {
  printf 'static check failed: %s\n' "$*" >&2
  exit 1
}

for binary in docker rg awk; do
  command -v "${binary}" >/dev/null || fail "${binary} is required"
done

docker compose -f docker-compose.local.yml config --quiet
docker compose -f docker-compose.ha-local.yml config --quiet
[[ -f environments/dev/eu-central-1/.terraform.lock.hcl ]] \
  || fail "Terraform provider lock file must be versioned"
[[ -f environments/prod/eu-central-1/.terraform.lock.hcl ]] \
  || fail "Production Terraform provider lock file must be versioned"
[[ -f environments/prod/eu-west-1/.terraform.lock.hcl ]] \
  || fail "EU West Terraform provider lock file must be versioned"
[[ -f environments/global/route53-failover/.terraform.lock.hcl ]] \
  || fail "Route 53 failover Terraform provider lock file must be versioned"

shell_files=()
while IFS= read -r shell_file; do
  shell_files+=("/workspace/${shell_file}")
done < <(rg --files -g '*.sh')
(( ${#shell_files[@]} > 0 )) || fail "no shell files found"
docker run --rm -v "${ROOT_DIR}:/workspace:ro" --entrypoint /bin/bash "${STEP_CA_IMAGE}" -n \
  "${shell_files[@]}"

while IFS= read -r image; do
  [[ "${image}" == *'${'* ]] && continue
  [[ "${image}" == *@sha256:* ]] || fail "container image is not digest-pinned: ${image}"
done < <(rg --no-filename '^\s*image:' docker-compose.local.yml docker-compose.ha-local.yml pki/config | sed -E 's/.*image:[[:space:]]*//')

while IFS= read -r image; do
  [[ "${image}" == *@sha256:* ]] || fail "Dockerfile base image is not digest-pinned: ${image}"
done < <(rg --no-filename '^FROM ' -g 'Dockerfile*' | awk '{print $2}')

if rg -i --glob '*.tf' 'tls_private_key|private_key_pem|private_key' modules environments; then
  fail "Terraform must not manage or carry a CA private key"
fi

if awk '/data "aws_iam_policy_document" "root"/{in_root=1} /data "aws_iam_policy_document" "intermediate"/{in_root=0} in_root && /runtime_role_arn/{found=1} END{exit !found}' modules/kms-ca/main.tf; then
  fail "root key policy must not grant the runtime role access"
fi

rg --quiet 'is_enabled\s*=\s*var\.root_key_enabled' modules/kms-ca/main.tf \
  || fail "root key enablement must remain explicit"
rg --quiet 'kms:Sign' modules/kms-ca/main.tf \
  || fail "KMS signing permission missing"
rg --quiet 'kms:Sign' environments/dev/eu-central-1/main.tf \
  || fail "runtime IAM KMS permission missing"
rg --quiet 'chown 1000:1000 /var/lib/step-ca' modules/step-ca-ec2/templates/pki-runtime.service.tftpl \
  || fail "step-ca writable state directory must match the container user"
rg --quiet 'AmazonSSMManagedInstanceCore' modules/step-ca-ec2/main.tf \
  || fail "runtime administration must use SSM rather than SSH"
rg --quiet 'AmazonSSMManagedInstanceCore' modules/step-ca-ha/main.tf \
  || fail "HA runtime administration must use SSM rather than SSH"
for runtime_template in modules/step-ca-ec2/templates/pki-runtime.service.tftpl modules/step-ca-ha/templates/pki-runtime-ha.service.tftpl; do
  rg --fixed-strings --quiet 'https://github.com/docker/compose/releases/download/v5.3.1/docker-compose-linux-aarch64' "${runtime_template}" \
    || fail "runtime must install a pinned Docker Compose plugin: ${runtime_template}"
  rg --fixed-strings --quiet 'aa611e811d0ea25897839c404bfb5bf93ce706dc51c500a4457890f5d0606a86' "${runtime_template}" \
    || fail "runtime must verify the Docker Compose plugin checksum: ${runtime_template}"
done
rg --quiet 'manage_master_user_password\s*=\s*true' modules/postgres/main.tf \
  || fail "RDS password must be AWS-managed rather than a Terraform input"
rg --quiet 'instance_refresh' modules/step-ca-ha/main.tf \
  || fail "HA runtime must use an Auto Scaling rolling refresh"
rg --quiet 'min_healthy_percentage\s*=\s*50' modules/step-ca-ha/main.tf \
  || fail "HA refresh must retain at least half of the capacity"
rg --quiet 'create_root_key\s*=\s*false' environments/prod/eu-west-1/main.tf \
  || fail "EU West must not create a competing root key"
rg --quiet 'failover_routing_policy' modules/route53-failover/main.tf \
  || fail "Global endpoint must use Route 53 failover routing"
rg --quiet 'google_oidc_client_secret_arn' modules/step-ca-ec2/main.tf \
  || fail "Lean runtime must scope Google OIDC secret access"
rg --quiet 'google_oidc_client_secret_arn' modules/step-ca-ha/main.tf \
  || fail "HA runtime must scope Google OIDC secret access"
rg --quiet 'gitlab_broker_jwk_secret_arn' modules/step-ca-ec2/main.tf \
  || fail "Lean runtime must scope GitLab broker key access"
rg --quiet 'gitlab_broker_jwk_secret_arn' modules/step-ca-ha/main.tf \
  || fail "HA runtime must scope GitLab broker key access"
rg --quiet 'attribute_not_exists\(jti\)' broker/internal/enrollment/replay.go \
  || fail "GitLab enrollment must atomically reject replayed token IDs"
rg --quiet 'ref_protected' broker/internal/enrollment/jwt.go \
  || fail "GitLab enrollment must check protected refs"
for compose_template in pki/config/step-ca-compose.yml.tftpl pki/config/step-ca-ha-compose.yml.tftpl; do
  rg --quiet 'rendered-ca.json' "${compose_template}" \
    || fail "runtime must mount the locally rendered CA configuration: ${compose_template}"
done

printf '%s\n' 'static checks passed'
