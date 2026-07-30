#!/bin/bash
set -euo pipefail

# This entrypoint is exclusively for the disposable Docker integration test. It
# intentionally creates software keys inside a named Docker volume. The AWS
# deployment never uses this file or any on-disk CA key.
export STEPPATH=/home/step

if [[ ! -f "${STEPPATH}/config/ca.json" ]]; then
  mkdir -p "${STEPPATH}"
  printf '%s\n' "${LOCAL_CA_PASSWORD:?LOCAL_CA_PASSWORD must be set}" > "${STEPPATH}/password"

  step ca init \
    --name "PKI local integration CA" \
    --dns "step-ca,localhost" \
    --address ":9000" \
    --provisioner "local-test" \
    --password-file "${STEPPATH}/password" \
    --provisioner-password-file "${STEPPATH}/password"

  # The integration test must prove that the authority policy blocks a SAN
  # outside the trust domain. Keep this in the local-only CA configuration.
  sed -i '/"authority": {/a\    "policy": {"x509": {"allow": {"dns": ["*.pki.test"]}}},' "${STEPPATH}/config/ca.json"
  install -d -m 0700 "${STEPPATH}/secrets"
  mv "${STEPPATH}/password" "${STEPPATH}/secrets/password"
fi

exec step-ca --password-file "${STEPPATH}/secrets/password" "${STEPPATH}/config/ca.json"
