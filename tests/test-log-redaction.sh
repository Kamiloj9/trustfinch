#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
step_ca_image="smallstep/step-ca@sha256:a2b17872915c193259b75a5474c398326f41bd199f0842093e52cf4182bc8270"

redacted_logs="$(docker run --rm --entrypoint /usr/bin/env \
  -v "${repo_root}/pki/runtime/step-ca-entrypoint.sh:/usr/local/bin/pki-step-ca-entrypoint:ro" \
  -v "${repo_root}/pki/runtime/redact-step-ca-logs.sh:/usr/local/bin/pki-redact-step-ca-logs:ro" \
  -v "${repo_root}/tests/fixtures/fake-step-ca.sh:/usr/local/bin/step-ca:ro" \
  "${step_ca_image}" \
    bash /usr/local/bin/pki-step-ca-entrypoint /home/step/config/ca.json)"

[[ "${redacted_logs}" != *token-value-that-must-not-be-logged* ]] \
  || { printf '%s\n' 'text one-time token was not redacted' >&2; exit 1; }
[[ "${redacted_logs}" != *json-token-value-that-must-not-be-logged* ]] \
  || { printf '%s\n' 'JSON one-time token was not redacted' >&2; exit 1; }
[[ "${redacted_logs}" == *'ott=[REDACTED]'* ]] \
  || { printf '%s\n' 'text one-time token redaction marker missing' >&2; exit 1; }
[[ "${redacted_logs}" == *'"ott":"[REDACTED]'* ]] \
  || { printf '%s\n' 'JSON one-time token redaction marker missing' >&2; exit 1; }

printf '%s\n' 'step-ca log redaction checks passed'
