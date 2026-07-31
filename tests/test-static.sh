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
rg --fixed-strings --quiet 'COMPOSE_ARCH="x86_64"' tests/test-runtime-bootstrap.sh \
  || fail "runtime bootstrap test must support x86_64 CI runners"
rg --fixed-strings --quiet 'docker-compose-linux-${COMPOSE_ARCH}' tests/test-runtime-bootstrap.sh \
  || fail "runtime bootstrap test must select a Docker Compose binary by architecture"
rg --fixed-strings --quiet "awk -F: 'NR == 1 { print \$NF }'" tests/test-container-image-supply-chain.sh \
  || fail "supply-chain test must select one Docker registry port mapping"
rg --fixed-strings --quiet 'HOST_USER="$(id -u):$(id -g)"' tests/test-iac.sh \
  || fail "Terraform validation must use the invoking user for temporary fixtures"
rg --fixed-strings --quiet 'FROM --platform=$BUILDPLATFORM golang@sha256:' broker/iam-lambda.Dockerfile \
  || fail "IAM broker must build natively before cross-compiling its Lambda output"
rg --fixed-strings --quiet 'chmod 0777 "${WORK_DIR}"' tests/test-local-recovery.sh \
  || fail "recovery test fixtures must be accessible to the Step CLI container"
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
rg --quiet 'authorization_type = "AWS_IAM"' modules/iam-enrollment-gateway/main.tf \
  || fail "IAM enrollment must require API Gateway AWS_IAM authorization"
rg --quiet 'NormalizeAssumedRoleARN' broker/internal/iam/config.go \
  || fail "IAM enrollment must normalize only trusted assumed-role ARNs"
rg --quiet 'execute-api:Invoke' modules/iam-enrollment-gateway/main.tf \
  || fail "IAM enrollment must emit a least-privilege caller invoke policy"
rg --quiet 'aws_backup_plan' modules/backup/main.tf \
  || fail "Lean CA state must have a Terraform-managed AWS Backup plan"
rg --quiet 'resources\s*=\s*var\.resource_arns' modules/backup/main.tf \
  || fail "Lean CA-state backup must use an explicit resource selection"
rg --quiet 'AWSBackupServiceRolePolicyForRestores' modules/backup/main.tf \
  || fail "Lean CA-state backup role must support the documented restore workflow"
rg --quiet 'failover\.pki\.test' tests/test-local-ha.sh \
  || fail "HA integration must issue from the secondary CA after primary loss"
rg --quiet '^test:.*test-recovery' Makefile \
  || fail "all local checks must include the CA state recovery exercise"
rg --quiet 'test-local-recovery.sh' Makefile \
  || fail "the recovery test target must execute the CA state recovery exercise"
rg --quiet 'recovered CA accepted renewal' tests/test-local-recovery.sh \
  || fail "local CA recovery must prove pre-backup revocation state is restored"
rg --quiet 'NumberOfBackupJobsFailed' modules/backup/main.tf \
  || fail "Lean CA-state backup failures must alert"
rg --quiet 'state_volume_id' modules/step-ca-ec2/outputs.tf \
  || fail "Lean CA backup must identify its exact state volume"
rg --quiet 'backup_retention_days' environments/dev/eu-central-1/main.tf \
  || fail "Lean environment must configure CA-state backup retention"
rg --quiet 'backup_retention_period\s*=\s*var\.backup_retention_days' modules/postgres/main.tf \
  || fail "Production PostgreSQL must retain point-in-time recovery backups"
for environment in environments/dev/eu-central-1 environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'type = "ACME"' "${environment}/main.tf" \
    || fail "ACME provisioner must be explicitly rendered only from reviewed input: ${environment}"
  rg --quiet 'var\.acme == null \? \[\] : var\.acme\.dns_allowlist' "${environment}/main.tf" \
    || fail "ACME DNS allowlist must be explicit: ${environment}"
done
rg --quiet -- '--use-aliases' tests/test-local-ca.sh \
  || fail "local ACME HTTP-01 test must use its isolated challenge alias"
rg --quiet 'step ca provisioner add acme --type ACME' docker/step-ca/local-entrypoint.sh \
  || fail "local test CA must enable the ACME provisioner"
rg --quiet 'rejected-acme\.crt' tests/test-local-ca.sh \
  || fail "local ACME test must reject an out-of-policy order"
rg --fixed-strings --quiet -- '--out "${temporary_certificate}"' clients/step-renewer/renew-step-certificate.sh \
  || fail "renewal helper must write to a temporary certificate first"
rg --fixed-strings --quiet 'mv -f "${temporary_certificate}" "${certificate_path}"' clients/step-renewer/renew-step-certificate.sh \
  || fail "renewal helper must atomically replace the live certificate"
rg --quiet 'max_attempts' clients/step-renewer/renew-step-certificate.sh \
  || fail "renewal helper must use bounded retry attempts"
rg --quiet 'RandomizedDelaySec' clients/step-renewer/systemd/pki-certificate-renew.timer \
  || fail "renewal timer must add scheduling jitter"
rg --quiet 'step ca revoke' tests/test-local-ca.sh \
  || fail "local CA integration must prove passive revocation blocks renewal"
rg --quiet 'passive revocation' runbooks/revocation.md \
  || fail "revocation model must be documented honestly"
for runtime_template in pki/config/step-ca-compose.yml.tftpl pki/config/step-ca-ha-compose.yml.tftpl; do
  rg --quiet 'pki-step-ca-entrypoint' "${runtime_template}" \
    || fail "step-ca runtime must use the log-redacting entrypoint: ${runtime_template}"
  rg --quiet 'pki-redact-step-ca-logs' "${runtime_template}" \
    || fail "step-ca runtime must mount the log redactor: ${runtime_template}"
done
rg --quiet 'ott=' pki/runtime/redact-step-ca-logs.sh \
  || fail "step-ca log redactor must remove one-time tokens"
rg --quiet 'mkfifo' pki/runtime/step-ca-entrypoint.sh \
  || fail "step-ca log boundary must drain a FIFO before shutdown"
for local_entrypoint in docker/step-ca/local-entrypoint.sh docker/step-ca/local-ha-entrypoint.sh; do
  rg --quiet '"logger": \{"format": "json"\}' "${local_entrypoint}" \
    || fail "local CA must use production-compatible JSON request logs: ${local_entrypoint}"
done
rg --quiet 'IssuedCertificates' modules/observability/main.tf \
  || fail "observability must record issued certificates by provisioner"
rg --quiet 'CA5xxResponses' modules/observability/main.tf \
  || fail "observability must alert on CA server errors"
rg --quiet 'SignLatencyNanoseconds' modules/observability/main.tf \
  || fail "observability must record signing latency"
rg --quiet 'IntermediateKmsSignErrors' modules/observability/main.tf \
  || fail "observability must alert on failed intermediate KMS signing"
rg --quiet 'IntermediateKmsSigns' modules/observability/main.tf \
  || fail "observability must record intermediate KMS signing volume"
rg --quiet 'intermediate_kms_sign_alarm_threshold' modules/observability/main.tf \
  || fail "observability must support a reviewed intermediate KMS signing threshold"
rg --quiet 'UnHealthyHostCount' modules/observability/main.tf \
  || fail "observability must alert when an HA step-ca target is unhealthy"
rg --quiet 'HTTPCode_Target_5XX_Count' modules/observability/main.tf \
  || fail "observability must alert on ALB target 5xx responses"
rg --quiet 'FreeStorageSpace' modules/observability/main.tf \
  || fail "observability must alert on low RDS storage"
rg --quiet 'disk_used_percent' modules/observability/main.tf \
  || fail "observability must alert on PKI host disk use"
for runtime_template in modules/step-ca-ec2/templates/pki-runtime.service.tftpl modules/step-ca-ha/templates/pki-runtime-ha.service.tftpl; do
  rg --quiet 'amazon-cloudwatch-agent' "${runtime_template}" \
    || fail "PKI runtime must install the CloudWatch Agent: ${runtime_template}"
  rg --quiet 'PKIName' "${runtime_template}" \
    || fail "PKI host metrics must be rolled up by PKI name: ${runtime_template}"
  rg --quiet 'pki-verify-runtime-artifacts' "${runtime_template}" \
    || fail "PKI runtime must embed the artifact manifest verifier: ${runtime_template}"
  rg --quiet 'findutils' "${runtime_template}" \
    || fail "PKI runtime must install findutils for fail-closed artifact inventory checks: ${runtime_template}"
  rg --quiet 'pki-verify-container-images' "${runtime_template}" \
    || fail "PKI runtime must embed the Cosign container-image verifier: ${runtime_template}"
done
rg --quiet 'CloudWatchAgentServerPolicy' modules/step-ca-ec2/main.tf \
  || fail "Lean runtime must authorize CloudWatch Agent metrics"
rg --quiet 'CloudWatchAgentServerPolicy' modules/step-ca-ha/main.tf \
  || fail "HA runtime must authorize CloudWatch Agent metrics"
rg --quiet 'aws_wafv2_web_acl' modules/step-ca-ha/main.tf \
  || fail "HA deployment must protect the public ALB with WAF"
rg --quiet 'aggregate_key_type[[:space:]]*=[[:space:]]*"IP"' modules/step-ca-ha/main.tf \
  || fail "WAF rate limit must be applied per source IP"
rg --quiet 'sampled_requests_enabled[[:space:]]*=[[:space:]]*false' modules/step-ca-ha/main.tf \
  || fail "WAF must not sample enrollment requests"
for environment in environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'load_balancer_arn_suffix' "${environment}/main.tf" \
    || fail "HA observability must receive the ALB metric dimension: ${environment}"
  rg --quiet 'database_instance_identifier' "${environment}/main.tf" \
    || fail "HA observability must receive the RDS metric dimension: ${environment}"
  rg --quiet 'enable_waf_rate_limit' "${environment}/main.tf" \
    || fail "HA deployment must pass the reviewed WAF configuration: ${environment}"
done
for environment in environments/dev/eu-central-1 environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'runtime_log_group_name' "${environment}/main.tf" \
    || fail "observability must receive the sanitized runtime log group: ${environment}"
done
for environment in environments/dev/eu-central-1 environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'runtime/step-ca/step-ca-entrypoint\.sh' "${environment}/main.tf" \
    || fail "runtime must publish the log-redacting entrypoint: ${environment}"
  rg --quiet 'runtime/step-ca/redact-step-ca-logs\.sh' "${environment}/main.tf" \
    || fail "runtime must publish the log redactor: ${environment}"
done
rg --quiet 'sts:AssumeRoleWithWebIdentity' modules/gitlab-terraform-oidc/main.tf \
  || fail "GitLab Terraform roles must use web-identity STS"
rg --quiet 'StringEquals' modules/gitlab-terraform-oidc/main.tf \
  || fail "GitLab Terraform trust must use exact claim matching"
rg --quiet 'max_session_duration\s*=\s*3600' modules/gitlab-terraform-oidc/main.tf \
  || fail "GitLab Terraform sessions must be limited to one hour"
rg --quiet 'permissions_boundary' modules/gitlab-terraform-oidc/main.tf \
  || fail "GitLab Terraform roles must have a permission boundary"
rg --quiet 'id_tokens:' .gitlab-ci.yml \
  || fail "GitLab pipeline must request an ID token"
rg --quiet 'aud: sts.amazonaws.com' .gitlab-ci.yml \
  || fail "GitLab pipeline ID token must target AWS STS"
rg --quiet 'AWS_WEB_IDENTITY_TOKEN_FILE' .gitlab-ci.yml \
  || fail "GitLab pipeline must use the standard AWS web-identity token file"
rg --quiet 'when: manual' .gitlab-ci.yml \
  || fail "GitLab Terraform apply must require an explicit manual action"
if rg --glob '.gitlab-ci.yml' --quiet 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)\s*:'; then
  fail "GitLab pipeline must not define static AWS access keys"
fi
for environment in environments/dev/eu-central-1 environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'gitlab_terraform_deployment' "${environment}/main.tf" \
    || fail "GitLab Terraform deployment roles must be available in ${environment}"
  rg --quiet 'runtime_artifact_signing' "${environment}/main.tf" \
    || fail "KMS runtime-artifact signing must be available in ${environment}"
done
rg --quiet 'ApprovedReleaseSignersOnly' modules/runtime-artifact-signing/main.tf \
  || fail "runtime artifact KMS key must restrict signing to approved release roles"
rg --quiet 'ECDSA_SHA_256' modules/runtime-artifact-signing/main.tf \
  || fail "runtime artifact KMS key must restrict signing algorithm"
rg --quiet 'setintersection' modules/runtime-artifact-signing/main.tf \
  || fail "runtime artifact release signers must be distinct from key administrators"
rg --quiet 'ReleaseSignerPublishesSignedManifestOnly' modules/step-ca-ec2/main.tf \
  || fail "Lean artifact bucket must limit signer writes to manifest files"
rg --quiet 'ReleaseSignerPublishesSignedManifestOnly' modules/step-ca-ha/main.tf \
  || fail "HA artifact bucket must limit signer writes to manifest files"
rg --quiet 'runtime.manifest.sig' pki/runtime/verify-runtime-artifacts.sh \
  || fail "runtime verifier must require a detached signature"
rg --quiet 'unmanifested runtime artifact' pki/runtime/verify-runtime-artifacts.sh \
  || fail "runtime verifier must reject unmanifested files"
for environment in environments/dev/eu-central-1 environments/prod/eu-central-1 environments/prod/eu-west-1; do
  rg --quiet 'runtime_artifact_signing_guard' "${environment}/main.tf" \
    || fail "runtime artifact signing must reject a self-signing runtime role in ${environment}"
  rg --quiet 'runtime_image_signing_guard' "${environment}/main.tf" \
    || fail "container image signing must require explicit signed image mirrors in ${environment}"
  rg --quiet 'container_image_ecr_repository_arns' "${environment}/main.tf" \
    || fail "container image ECR pull scope must be wired in ${environment}"
done
rg --quiet 'verify-attestation' pki/runtime/verify-container-images.sh \
  || fail "runtime image verifier must require an SPDX attestation"
rg --quiet 'insecure-ignore-tlog' pki/runtime/verify-container-images.sh \
  || fail "local image supply-chain tests must opt in explicitly when skipping transparency-log verification"
rg --quiet 'if \[\[ "\$\{allow_insecure_no_tlog\}" == true \]\]' pki/runtime/verify-container-images.sh \
  || fail "runtime image verification must require an explicit test-only switch before skipping transparency-log verification"
if rg --quiet 'insecure-ignore-tlog' modules/step-ca-ec2/templates/pki-runtime.service.tftpl modules/step-ca-ha/templates/pki-runtime-ha.service.tftpl; then
  fail "runtime bootstrap must never disable Cosign transparency-log verification"
fi
rg --quiet 'scanners="vuln,secret"' ceremony/sign-container-image.sh \
  || fail "container release signing must scan vulnerabilities and secrets by default"
rg --quiet 'spdx-json' ceremony/sign-container-image.sh \
  || fail "container release signing must generate SPDX SBOMs"
rg --quiet 'AWS_SESSION_TOKEN' ceremony/sign-container-image.sh \
  || fail "container release signing must forward temporary AWS credentials to Cosign"
rg --quiet 'PullSignedRuntimeImagesOnly' modules/step-ca-ec2/main.tf \
  || fail "Lean runtime must scope private ECR pulls to signed image repositories"
rg --quiet 'PullSignedRuntimeImagesOnly' modules/step-ca-ha/main.tf \
  || fail "HA runtime must scope private ECR pulls to signed image repositories"
rg --quiet 'get-login-password' modules/step-ca-ec2/templates/pki-runtime.service.tftpl \
  || fail "Lean runtime must obtain a short-lived private ECR login before image verification"
rg --quiet 'get-login-password' modules/step-ca-ha/templates/pki-runtime-ha.service.tftpl \
  || fail "HA runtime must obtain a short-lived private ECR login before image verification"
rg --quiet 'awskms' runbooks/container-image-supply-chain.md \
  || fail "container signing runbook must use AWS KMS rather than a persistent private key"
bash -n pki/runtime/step-ca-entrypoint.sh pki/runtime/redact-step-ca-logs.sh pki/runtime/verify-runtime-artifacts.sh pki/runtime/verify-container-images.sh ceremony/sign-runtime-artifacts.sh ceremony/sign-container-image.sh \
  || fail "step-ca log-boundary scripts must have valid Bash syntax"
for compose_template in pki/config/step-ca-compose.yml.tftpl pki/config/step-ca-ha-compose.yml.tftpl; do
  rg --quiet 'rendered-ca.json' "${compose_template}" \
    || fail "runtime must mount the locally rendered CA configuration: ${compose_template}"
done

printf '%s\n' 'static checks passed'
