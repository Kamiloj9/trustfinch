#!/bin/bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: sign-runtime-artifacts.sh --bucket BUCKET --key-id KMS_KEY_ID [--prefix runtime]' >&2
  exit 2
}

bucket=""
key_id=""
prefix="runtime"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      bucket="${2:-}"
      shift 2
      ;;
    --key-id)
      key_id="${2:-}"
      shift 2
      ;;
    --prefix)
      prefix="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "${bucket}" && -n "${key_id}" ]] || usage
[[ "${prefix}" =~ ^[A-Za-z0-9._/-]+$ && "${prefix}" != /* && "${prefix}" != *..* ]] || {
  printf '%s\n' 'prefix must be a relative S3 key prefix without ..' >&2
  exit 2
}

work_dir="$(mktemp -d -t pki-runtime-artifacts.XXXXXX)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

runtime_dir="${work_dir}/runtime"
mkdir -p "${runtime_dir}"
aws s3 sync "s3://${bucket}/${prefix}" "${runtime_dir}" --exact-timestamps \
  --exclude runtime.manifest --exclude runtime.manifest.sig

manifest="${runtime_dir}/runtime.manifest"
artifact_list="${work_dir}/artifact-list"
find -P "${runtime_dir}" -type f \
  ! -path "${runtime_dir}/runtime.manifest" \
  ! -path "${runtime_dir}/runtime.manifest.sig" \
  -print0 | sort -z > "${artifact_list}"
while IFS= read -r -d '' artifact_path; do
  relative_path="${artifact_path#${runtime_dir}/}"
  [[ "${relative_path}" =~ ^([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$ ]] || {
    printf 'runtime artifact name is not allowed in a signed manifest: %s\n' "${relative_path}" >&2
    exit 1
  }
  sha256sum "${artifact_path}" | sed "s#  ${artifact_path}#  ${relative_path}#" >> "${manifest}"
done < "${artifact_list}"

[[ -s "${manifest}" ]] || {
  printf '%s\n' 'refusing to sign an empty runtime artifact manifest' >&2
  exit 1
}
[[ $(wc -c < "${manifest}") -le 4096 ]] || {
  printf '%s\n' 'runtime manifest exceeds the KMS raw-message size limit; split the release before signing' >&2
  exit 1
}

aws kms sign \
  --key-id "${key_id}" \
  --message-type RAW \
  --message "fileb://${manifest}" \
  --signing-algorithm ECDSA_SHA_256 \
  --query Signature \
  --output text | base64 --decode > "${runtime_dir}/runtime.manifest.sig"

aws s3 cp "${manifest}" "s3://${bucket}/${prefix}/runtime.manifest"
aws s3 cp "${runtime_dir}/runtime.manifest.sig" "s3://${bucket}/${prefix}/runtime.manifest.sig"
printf 'signed %s runtime artifacts with KMS key %s\n' "$(wc -l < "${manifest}")" "${key_id}"
