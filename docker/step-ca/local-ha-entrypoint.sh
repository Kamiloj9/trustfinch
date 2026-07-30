#!/bin/bash
set -euo pipefail

# Local-only Postgres exercise for the HA configuration. This creates disposable
# software keys in a Docker volume; it does not emulate AWS KMS or an ALB.
export STEPPATH=/home/step

if [[ ! -f "${STEPPATH}/config/ca.json" ]]; then
  mkdir -p "${STEPPATH}"
  printf '%s\n' "${LOCAL_CA_PASSWORD:?LOCAL_CA_PASSWORD must be set}" > "${STEPPATH}/password"

  step ca init \
    --name "PKI local HA integration CA" \
    --dns "step-ca,step-ca-secondary,localhost" \
    --address ":9000" \
    --provisioner "local-test" \
    --password-file "${STEPPATH}/password" \
    --provisioner-password-file "${STEPPATH}/password"

  sed -i '/"db": {/,/},/c\  "db": {"type": "postgresql", "dataSource": "postgresql://stepca:local-test-password-not-for-production@postgres:5432/stepca?sslmode=disable"},' "${STEPPATH}/config/ca.json"
  sed -i '/"authority": {/a\    "policy": {"x509": {"allow": {"dns": ["*.pki.test"]}}},' "${STEPPATH}/config/ca.json"
  # Match the production logger format so local HA traffic uses the same
  # CloudWatch metric-filter field schema.
  sed -i '/"authority": {/i\  "logger": {"format": "json"},' "${STEPPATH}/config/ca.json"
  install -d -m 0700 "${STEPPATH}/secrets"
  mv "${STEPPATH}/password" "${STEPPATH}/secrets/password"
fi

exec step-ca --password-file "${STEPPATH}/secrets/password" "${STEPPATH}/config/ca.json"
