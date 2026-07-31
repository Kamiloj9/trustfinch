#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${ROOT_DIR}/.local/trustfinch"
TERRAFORM_IMAGE="hashicorp/terraform@sha256:6bbb82d575aa7bd4f0a2c6e3a0838ab9590426c08a71d7a2783643f01004d356"
AWS_CLI_IMAGE="amazon/aws-cli@sha256:211d32cc6c64665ff5bcd0d3df1b169bdc106388e9451cfc115466da1f3c6099"
STEP_CA_IMAGE="smallstep/step-ca@sha256:a2b17872915c193259b75a5474c398326f41bd199f0842093e52cf4182bc8270"

stage="bootstrap"
config_file="${LOCAL_DIR}/dev-eu-central-1.tfvars"
backend_file=""
aws_config_dir="${HOME:-}/.aws"
aws_profile="default"
non_interactive=false
dry_run=false
confirmation=""
work_dir=""

usage() {
  printf '%s\n' \
    'usage: scripts/trustfinch-setup.sh [options]' \
    '' \
    'Safe Lean-dev setup guide for environments/dev/eu-central-1.' \
    '' \
    'Stages:' \
    '  bootstrap    Create/validate local config and apply with the root disabled (default).' \
    '  enable-root  Temporarily enable the root key, then stop for the human ceremony.' \
    '  publish      Upload reviewed public ceremony certificates only.' \
    '  seal         Disable the root key and verify the CA health and root fingerprint.' \
    '' \
    'Options:' \
    '  --stage NAME              One of bootstrap, enable-root, publish, or seal.' \
    '  --config PATH             Local non-secret Terraform variables file.' \
    '  --backend-config PATH     Existing hardened S3 backend.hcl file (required).' \
    '  --aws-config-dir PATH     AWS shared config directory (default: $HOME/.aws).' \
    '  --aws-profile NAME        Short-lived AWS profile to use (default: default).' \
    '  --non-interactive         Require --config and --confirm; never prompt.' \
    '  --confirm TEXT            Exact stage confirmation for non-interactive use.' \
    '  --dry-run                 Validate local inputs and print the next safe action only.' \
    '  -h, --help                Show this help.'
}

fail() {
  printf 'trustfinch setup: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${work_dir}" && "${work_dir}" == /tmp/trustfinch-terraform.* && -d "${work_dir}" ]]; then
    rm -rf "${work_dir}"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null || fail "$1 is required"
}

canonical_file() {
  local path="$1"
  [[ -f "${path}" && ! -L "${path}" ]] || fail "regular file required: ${path}"
  (cd "$(dirname "${path}")" && printf '%s/%s\n' "$(pwd)" "$(basename "${path}")")
}

canonical_directory() {
  local path="$1"
  [[ -d "${path}" && ! -L "${path}" ]] || fail "directory required: ${path}"
  (cd "${path}" && pwd)
}

prompt_required() {
  local label="$1"
  local value=""
  [[ "${non_interactive}" == false ]] || fail "--non-interactive requires a prepared --config file"
  while [[ -z "${value}" ]]; do
    printf '%s: ' "${label}" >&2
    IFS= read -r value
  done
  printf '%s' "${value}"
}

confirm_stage() {
  local expected="$1"
  local supplied="${confirmation}"

  if [[ "${non_interactive}" == false && -z "${supplied}" ]]; then
    printf 'Type %s to continue: ' "${expected}" >&2
    IFS= read -r supplied
  fi
  [[ "${supplied}" == "${expected}" ]] || fail "confirmation did not match ${expected}"
}

validate_fqdn() {
  local value="$1"
  [[ "${value}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || return 1
  [[ "${value}" != *example* && "${value}" != *localhost* ]]
}

validate_cidr() {
  local value="$1"
  [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]
}

validate_iam_role_arn() {
  local value="$1"
  [[ "${value}" =~ ^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$ ]]
}

validate_hosted_zone_id() {
  local value="$1"
  [[ -z "${value}" || "${value}" =~ ^Z[A-Z0-9]+$ ]]
}

config_value() {
  local key="$1"
  awk -F= -v key="${key}" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", value)
      print value
      exit
    }
  ' "${config_file}"
}

validate_config() {
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || fail "configuration file is missing: ${config_file}"
  if rg --quiet '^[[:space:]]*root_key_enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${config_file}"; then
    fail "configuration must keep root_key_enabled = false; the guide controls the temporary ceremony override"
  fi

  local ca_fqdn internal_dns_suffix trust_domain cidr
  ca_fqdn="$(config_value ca_fqdn)"
  internal_dns_suffix="$(config_value internal_dns_suffix)"
  trust_domain="$(config_value trust_domain)"
  cidr="$(config_value allowed_https_cidrs | tr -d '[] "' | cut -d, -f1)"

  validate_fqdn "${ca_fqdn}" || fail "ca_fqdn must be a real lowercase FQDN, not an example value"
  validate_fqdn "${internal_dns_suffix}" || fail "internal_dns_suffix must be a real lowercase DNS suffix"
  validate_fqdn "${trust_domain}" || fail "trust_domain must be a real lowercase DNS suffix"
  validate_cidr "${cidr}" || fail "allowed_https_cidrs must begin with a valid IPv4 CIDR"
  rg --quiet '^[[:space:]]*key_administrator_arns[[:space:]]*=[[:space:]]*\[[^]]+\]' "${config_file}" \
    || fail "key_administrator_arns must contain at least one role"
  rg --quiet '^[[:space:]]*root_ceremony_role_arns[[:space:]]*=[[:space:]]*\[[^]]+\]' "${config_file}" \
    || fail "root_ceremony_role_arns must contain at least one role"
}

validate_backend() {
  backend_file="$(canonical_file "${backend_file}")"
  rg --quiet '^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"[a-z0-9.-]+"[[:space:]]*$' "${backend_file}" \
    || fail "backend.hcl must define an S3 bucket"
  rg --quiet '^[[:space:]]*key[[:space:]]*=[[:space:]]*"[^\"]+"[[:space:]]*$' "${backend_file}" \
    || fail "backend.hcl must define a non-empty state key"
  rg --quiet '^[[:space:]]*encrypt[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${backend_file}" \
    || fail "backend.hcl must set encrypt = true"
  rg --quiet '^[[:space:]]*use_lockfile[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${backend_file}" \
    || fail "backend.hcl must set use_lockfile = true"
  if rg --ignore-case --quiet '(^|_)(access_key|secret_key|token)[[:space:]]*=' "${backend_file}"; then
    fail "backend.hcl must not contain credentials"
  fi
}

backend_bucket() {
  awk -F= '$1 ~ /^[[:space:]]*bucket[[:space:]]*$/ { gsub(/[[:space:]\"]/, "", $2); print $2; exit }' "${backend_file}"
}

validate_aws_configuration() {
  aws_config_dir="$(canonical_directory "${aws_config_dir}")"
  [[ "${aws_profile}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || fail "AWS profile contains unsupported characters"
  [[ -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_SECRET_ACCESS_KEY:-}" ]] \
    || fail "unset static AWS credential environment variables and use a short-lived profile"
  if rg --hidden --glob 'config' --glob 'credentials' --glob '*.ini' --ignore-case --quiet \
    'aws_(access_key_id|secret_access_key)' "${aws_config_dir}"; then
    fail "AWS config directory must not contain long-lived access keys"
  fi
}

aws_call() {
  docker run --rm \
    -e AWS_PROFILE="${aws_profile}" \
    -e AWS_SDK_LOAD_CONFIG=1 \
    -e AWS_EC2_METADATA_DISABLED=true \
    -v "${aws_config_dir}:/root/.aws:ro" \
    "${AWS_CLI_IMAGE}" "$@"
}

validate_live_backend() {
  local identity bucket versioning encryption public_access
  identity="$(aws_call sts get-caller-identity --query Arn --output text)"
  [[ "${identity}" == *":assumed-role/"* ]] || fail "AWS profile must resolve to a short-lived assumed-role session"
  bucket="$(backend_bucket)"
  aws_call s3api head-bucket --bucket "${bucket}" >/dev/null
  versioning="$(aws_call s3api get-bucket-versioning --bucket "${bucket}" --query Status --output text)"
  [[ "${versioning}" == "Enabled" ]] || fail "state bucket must have versioning enabled"
  encryption="$(aws_call s3api get-bucket-encryption --bucket "${bucket}" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
  [[ "${encryption}" == "AES256" || "${encryption}" == "aws:kms" ]] || fail "state bucket must use default encryption"
  public_access="$(aws_call s3api get-public-access-block --bucket "${bucket}" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text)"
  [[ "${public_access}" == $'True\tTrue\tTrue\tTrue' ]] || fail "state bucket must block all public access"
  printf 'Using short-lived AWS identity %s and hardened backend bucket %s.\n' "${identity}" "${bucket}"
}

write_interactive_config() {
  [[ "${non_interactive}" == false ]] || fail "--config must point to a prepared file in non-interactive mode"
  mkdir -p "${LOCAL_DIR}"
  [[ ! -e "${config_file}" ]] || confirm_stage "OVERWRITE LOCAL CONFIGURATION"

  local ca_fqdn internal_dns_suffix trust_domain allowed_cidr key_admin_role ceremony_role hosted_zone_id
  ca_fqdn="$(prompt_required 'CA FQDN (for example ca.pki.your-domain.com)')"
  internal_dns_suffix="$(prompt_required 'Internal DNS suffix')"
  trust_domain="$(prompt_required 'SPIFFE trust domain')"
  allowed_cidr="$(prompt_required 'HTTPS allow CIDR (for example 203.0.113.0/24)')"
  key_admin_role="$(prompt_required 'KMS key administrator role ARN')"
  ceremony_role="$(prompt_required 'Root ceremony and public certificate publisher role ARN')"
  printf 'Route 53 hosted zone ID (optional; leave empty when DNS is external): ' >&2
  IFS= read -r hosted_zone_id

  validate_fqdn "${ca_fqdn}" || fail "CA FQDN must be a real lowercase FQDN, not an example value"
  validate_fqdn "${internal_dns_suffix}" || fail "internal DNS suffix must be a real lowercase DNS suffix"
  validate_fqdn "${trust_domain}" || fail "SPIFFE trust domain must be a real lowercase DNS suffix"
  validate_cidr "${allowed_cidr}" || fail "HTTPS allow CIDR must be an IPv4 CIDR"
  validate_iam_role_arn "${key_admin_role}" || fail "KMS administrator role ARN is invalid"
  validate_iam_role_arn "${ceremony_role}" || fail "ceremony role ARN is invalid"
  validate_hosted_zone_id "${hosted_zone_id}" || fail "Route 53 hosted zone ID is invalid"

  umask 077
  {
    printf 'name = "trustfinch-dev"\n\n'
    printf 'ca_fqdn = "%s"\n' "${ca_fqdn}"
    printf 'internal_dns_suffix = "%s"\n' "${internal_dns_suffix}"
    printf 'trust_domain = "%s"\n' "${trust_domain}"
    printf 'allowed_https_cidrs = ["%s"]\n' "${allowed_cidr}"
    if [[ -n "${hosted_zone_id}" ]]; then
      printf 'hosted_zone_id = "%s"\n' "${hosted_zone_id}"
    else
      printf 'hosted_zone_id = null\n'
    fi
    printf '\nkey_administrator_arns = ["%s"]\n' "${key_admin_role}"
    printf 'root_ceremony_role_arns = ["%s"]\n' "${ceremony_role}"
    printf 'certificate_publisher_role_arns = ["%s"]\n' "${ceremony_role}"
    printf 'root_key_enabled = false\n'
  } >"${config_file}"
  printf 'Wrote local non-secret configuration to %s.\n' "${config_file}"
}

prepare_work_directory() {
  work_dir="$(mktemp -d -t trustfinch-terraform.XXXXXX)"
  docker run --rm \
    -v "${ROOT_DIR}:/source:ro" \
    -v "${work_dir}:/work" \
    --entrypoint /bin/sh \
    "${TERRAFORM_IMAGE}" \
    -ec 'tar --exclude=.git --exclude=.terraform --exclude=.local -C /source -cf - . | tar -C /work -xf -'
}

terraform_call() {
  docker run --rm \
    -e AWS_PROFILE="${aws_profile}" \
    -e AWS_SDK_LOAD_CONFIG=1 \
    -e AWS_EC2_METADATA_DISABLED=true \
    -v "${work_dir}:/work" \
    -v "${config_file}:/settings/terraform.tfvars:ro" \
    -v "${backend_file}:/settings/backend.hcl:ro" \
    -v "${aws_config_dir}:/root/.aws:ro" \
    -w /work/environments/dev/eu-central-1 \
    "${TERRAFORM_IMAGE}" "$@"
}

apply_terraform_stage() {
  local root_enabled="$1"
  local expected_confirmation="$2"
  local plan_file="/work/trustfinch-${stage}.tfplan"

  make -C "${ROOT_DIR}" test
  validate_live_backend
  prepare_work_directory
  terraform_call init -backend-config=/settings/backend.hcl -input=false
  terraform_call plan \
    -input=false \
    -lock-timeout=5m \
    -var-file=/settings/terraform.tfvars \
    -var="root_key_enabled=${root_enabled}" \
    -out="${plan_file}"
  confirm_stage "${expected_confirmation}"
  terraform_call apply -input=false -lock-timeout=5m "${plan_file}"
}

terraform_output() {
  local output_name="$1"
  cleanup
  work_dir=""
  prepare_work_directory
  terraform_call init -backend-config=/settings/backend.hcl -input=false >/dev/null
  terraform_call output -raw "${output_name}"
}

print_ceremony_instructions() {
  local root_key_id intermediate_key_id artifact_bucket
  root_key_id="$(terraform_output root_key_id)"
  intermediate_key_id="$(terraform_output intermediate_key_id)"
  artifact_bucket="$(terraform_output artifact_bucket)"
  printf '%s\n' \
    '' \
    'The root key is temporarily enabled. Stop here and complete the human ceremony:' \
    "  ROOT_KEY_ID=${root_key_id} INTERMEDIATE_KEY_ID=${intermediate_key_id} AWS_SHARED_CONFIG_DIR=${aws_config_dir} AWS_PROFILE=${aws_profile} AWS_REGION=eu-central-1 PKI_NAME=Trustfinch ceremony/create-hierarchy.sh" \
    'Review ceremony/output/root_ca.crt and ceremony/output/intermediate_ca.crt using an independent channel.' \
    "Then run this guide's publish stage with the same --config and --backend-config. Expected artifact bucket: ${artifact_bucket}" \
    'Do not deploy provisioners until their policy rows and negative tests are approved.'
}

publish_certificates() {
  local artifact_bucket
  [[ -f "${ROOT_DIR}/ceremony/output/root_ca.crt" && -f "${ROOT_DIR}/ceremony/output/intermediate_ca.crt" ]] \
    || fail "reviewed root_ca.crt and intermediate_ca.crt are required in ceremony/output"
  confirm_stage "PUBLISH PUBLIC CERTIFICATES"
  artifact_bucket="$(terraform_output artifact_bucket)"
  ARTIFACT_BUCKET="${artifact_bucket}" \
    AWS_SHARED_CONFIG_DIR="${aws_config_dir}" \
    AWS_PROFILE="${aws_profile}" \
    AWS_REGION=eu-central-1 \
    "${ROOT_DIR}/ceremony/publish-public-certificates.sh"
}

verify_ca() {
  local ca_fqdn root_certificate fingerprint
  root_certificate="${ROOT_DIR}/ceremony/output/root_ca.crt"
  [[ -f "${root_certificate}" ]] || fail "root certificate is required for verification: ${root_certificate}"
  ca_fqdn="$(config_value ca_fqdn)"
  fingerprint="$(docker run --rm -v "$(dirname "${root_certificate}"):/certs:ro" --entrypoint step "${STEP_CA_IMAGE}" certificate fingerprint /certs/root_ca.crt)"
  docker run --rm --network host --entrypoint step "${STEP_CA_IMAGE}" ca health --ca-url "https://${ca_fqdn}"
  docker run --rm --network host -e STEPPATH=/tmp/trustfinch-step --entrypoint step "${STEP_CA_IMAGE}" \
    ca bootstrap --ca-url "https://${ca_fqdn}" --fingerprint "${fingerprint}" --force
  printf 'CA health and root fingerprint verification passed for %s.\n' "${ca_fqdn}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      stage="${2:-}"
      shift 2
      ;;
    --config)
      config_file="${2:-}"
      shift 2
      ;;
    --backend-config)
      backend_file="${2:-}"
      shift 2
      ;;
    --aws-config-dir)
      aws_config_dir="${2:-}"
      shift 2
      ;;
    --aws-profile)
      aws_profile="${2:-}"
      shift 2
      ;;
    --non-interactive)
      non_interactive=true
      shift
      ;;
    --confirm)
      confirmation="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

case "${stage}" in
  bootstrap|enable-root|publish|seal) ;;
  *) usage >&2; fail "unsupported stage: ${stage}" ;;
esac
[[ -n "${backend_file}" ]] || fail "--backend-config is required; Trustfinch never creates Terraform state infrastructure"

if [[ "${config_file}" != /* ]]; then
  config_file="${ROOT_DIR}/${config_file}"
fi
if [[ "${backend_file}" != /* ]]; then
  backend_file="${ROOT_DIR}/${backend_file}"
fi
if [[ "${aws_config_dir}" != /* ]]; then
  aws_config_dir="${ROOT_DIR}/${aws_config_dir}"
fi

if [[ "${dry_run}" == false && "$(dirname "${config_file}")" != "${LOCAL_DIR}" ]]; then
  fail "live setup configuration must stay under ${LOCAL_DIR} so it remains ignored by Git"
fi

if [[ "${stage}" == bootstrap && ! -f "${config_file}" ]]; then
  [[ "${dry_run}" == false ]] || fail "--dry-run requires a prepared --config file"
  write_interactive_config
fi

require_command rg
require_command awk
validate_backend
validate_config

if [[ "${dry_run}" == true ]]; then
  printf 'Dry run passed for stage %s. No Docker, AWS, Terraform, or tracked-file changes were made.\n' "${stage}"
  exit 0
fi

require_command docker
require_command make
require_command mktemp
validate_aws_configuration

case "${stage}" in
  bootstrap)
    apply_terraform_stage false "BOOTSTRAP TRUSTFINCH"
    printf 'Bootstrap completed with the root key disabled. Run --stage enable-root only for an approved ceremony.\n'
    ;;
  enable-root)
    apply_terraform_stage true "ENABLE ROOT"
    print_ceremony_instructions
    ;;
  publish)
    publish_certificates
    printf 'Public certificates were uploaded. Run --stage seal immediately to disable the root key.\n'
    ;;
  seal)
    apply_terraform_stage false "DISABLE ROOT"
    verify_ca
    ;;
esac
