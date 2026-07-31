#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMAZON_LINUX_IMAGE="amazonlinux@sha256:c4b0d324eaacbc5805ab5f147ba71963184752da90340bf0803c1034a170c8d1"
WORK_DIR="$(mktemp -d -t pki-artifact-signature.XXXXXX)"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

docker run --rm \
  -e HOST_GID="$(id -g)" \
  -e HOST_UID="$(id -u)" \
  -v "${ROOT_DIR}:/source:ro" \
  -v "${WORK_DIR}:/work" \
  --entrypoint /bin/bash \
  "${AMAZON_LINUX_IMAGE}" \
  -ec 'dnf install -y openssl findutils >/dev/null; mkdir -p /work/runtime/step-ca; printf "approved config\n" >/work/runtime/step-ca/ca.json; openssl ecparam -name prime256v1 -genkey -noout -out /work/signing-key.pem; openssl ec -in /work/signing-key.pem -pubout -out /work/signing-key.pub.pem >/dev/null 2>&1; (cd /work/runtime && sha256sum step-ca/ca.json >runtime.manifest && openssl dgst -sha256 -sign /work/signing-key.pem -out runtime.manifest.sig runtime.manifest); bash /source/pki/runtime/verify-runtime-artifacts.sh --runtime-dir /work/runtime --public-key /work/signing-key.pub.pem; printf "tampered config\n" >/work/runtime/step-ca/ca.json; if bash /source/pki/runtime/verify-runtime-artifacts.sh --runtime-dir /work/runtime --public-key /work/signing-key.pub.pem; then echo "tampered runtime artifact was accepted" >&2; exit 1; fi; printf "approved config\n" >/work/runtime/step-ca/ca.json; printf "unapproved artifact\n" >/work/runtime/unapproved; if bash /source/pki/runtime/verify-runtime-artifacts.sh --runtime-dir /work/runtime --public-key /work/signing-key.pub.pem; then echo "unmanifested runtime artifact was accepted" >&2; exit 1; fi; chown -R "${HOST_UID}:${HOST_GID}" /work'

printf '%s\n' 'runtime artifact signature checks passed'
