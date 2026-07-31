#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d -t trustfinch-setup-test.XXXXXX)"

cleanup() {
  if [[ -n "${WORK_DIR}" && "${WORK_DIR}" == /tmp/trustfinch-setup-test.* && -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'Trustfinch setup test failed: %s\n' "$*" >&2
  exit 1
}

config_file="${WORK_DIR}/dev.tfvars"
backend_file="${WORK_DIR}/backend.hcl"
status_before="$(git -C "${ROOT_DIR}" status --porcelain)"

printf '%s\n' \
  'name = "trustfinch-dev"' \
  'ca_fqdn = "ca.trustfinch.test"' \
  'internal_dns_suffix = "internal.trustfinch.test"' \
  'trust_domain = "internal.trustfinch.test"' \
  'allowed_https_cidrs = ["198.51.100.0/24"]' \
  'key_administrator_arns = ["arn:aws:iam::111122223333:role/trustfinch-kms-admin"]' \
  'root_ceremony_role_arns = ["arn:aws:iam::111122223333:role/trustfinch-ceremony"]' \
  'certificate_publisher_role_arns = ["arn:aws:iam::111122223333:role/trustfinch-ceremony"]' \
  'root_key_enabled = false' >"${config_file}"

printf '%s\n' \
  'bucket = "trustfinch-test-state"' \
  'key = "trustfinch/dev/eu-central-1/terraform.tfstate"' \
  'region = "eu-central-1"' \
  'encrypt = true' \
  'use_lockfile = true' >"${backend_file}"

output="$(bash "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  --stage bootstrap \
  --config "${config_file}" \
  --backend-config "${backend_file}" \
  --non-interactive \
  --dry-run)"
[[ "${output}" == *'Dry run passed for stage bootstrap'* ]] || fail "valid bootstrap dry run did not pass"

for stage in enable-root publish seal; do
  output="$(bash "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
    --stage "${stage}" \
    --config "${config_file}" \
    --backend-config "${backend_file}" \
    --non-interactive \
    --dry-run)"
  [[ "${output}" == *"Dry run passed for stage ${stage}"* ]] || fail "${stage} dry run did not pass"
done

invalid_config="${WORK_DIR}/invalid-root.tfvars"
cp "${config_file}" "${invalid_config}"
sed -i.bak 's/root_key_enabled = false/root_key_enabled = true/' "${invalid_config}"
rm -f "${invalid_config}.bak"
if bash "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  --config "${invalid_config}" \
  --backend-config "${backend_file}" \
  --non-interactive \
  --dry-run >/dev/null 2>&1; then
  fail "root-enabled local configuration was accepted"
fi

example_config="${WORK_DIR}/example-domain.tfvars"
cp "${config_file}" "${example_config}"
sed -i.bak 's/ca.trustfinch.test/ca.example.internal/' "${example_config}"
rm -f "${example_config}.bak"
if bash "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  --config "${example_config}" \
  --backend-config "${backend_file}" \
  --non-interactive \
  --dry-run >/dev/null 2>&1; then
  fail "example CA FQDN was accepted"
fi

if bash "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  --config "${config_file}" \
  --backend-config "${backend_file}" \
  --non-interactive >/dev/null 2>&1; then
  fail "live setup accepted a configuration outside .local/trustfinch"
fi

rg --fixed-strings --quiet 'apply_terraform_stage true "ENABLE ROOT"' "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  || fail "root-enable stage does not require its exact confirmation"
rg --fixed-strings --quiet 'confirm_stage "PUBLISH PUBLIC CERTIFICATES"' "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  || fail "publish stage does not require its exact confirmation"
rg --fixed-strings --quiet 'apply_terraform_stage false "DISABLE ROOT"' "${ROOT_DIR}/scripts/trustfinch-setup.sh" \
  || fail "seal stage does not require its exact confirmation"

status_after="$(git -C "${ROOT_DIR}" status --porcelain)"
[[ "${status_before}" == "${status_after}" ]] || fail "dry-run changed the checkout"

printf 'Trustfinch setup dry-run checks passed\n'
