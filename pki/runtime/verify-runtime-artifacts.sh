#!/bin/bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: verify-runtime-artifacts.sh --runtime-dir DIR --public-key PEM' >&2
  exit 2
}

runtime_dir=""
public_key=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-dir)
      runtime_dir="${2:-}"
      shift 2
      ;;
    --public-key)
      public_key="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "${runtime_dir}" && -n "${public_key}" ]] || usage
[[ -d "${runtime_dir}" && -f "${public_key}" ]] || {
  printf '%s\n' 'runtime directory or public key is missing' >&2
  exit 1
}

manifest="${runtime_dir}/runtime.manifest"
signature="${runtime_dir}/runtime.manifest.sig"
[[ -f "${manifest}" && ! -L "${manifest}" && -f "${signature}" && ! -L "${signature}" ]] || {
  printf '%s\n' 'signed runtime manifest is missing or is a symlink' >&2
  exit 1
}

openssl dgst -sha256 -verify "${public_key}" -signature "${signature}" "${manifest}" >/dev/null || {
  printf '%s\n' 'runtime artifact manifest signature verification failed' >&2
  exit 1
}

declare -A manifest_paths=()
line_number=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  line_number=$((line_number + 1))
  [[ "${line}" =~ ^([0-9a-f]{64})\ \ (.+)$ ]] || {
    printf 'invalid manifest line %s\n' "${line_number}" >&2
    exit 1
  }

  expected_hash="${BASH_REMATCH[1]}"
  relative_path="${BASH_REMATCH[2]}"
  [[ "${relative_path}" =~ ^([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$ ]] || {
    printf 'unsafe manifest path on line %s\n' "${line_number}" >&2
    exit 1
  }
  [[ "${relative_path}" != "runtime.manifest" && "${relative_path}" != "runtime.manifest.sig" ]] || {
    printf 'manifest cannot list itself on line %s\n' "${line_number}" >&2
    exit 1
  }
  [[ -z "${manifest_paths[${relative_path}]:-}" ]] || {
    printf 'duplicate manifest path on line %s\n' "${line_number}" >&2
    exit 1
  }

  artifact_path="${runtime_dir}/${relative_path}"
  [[ -f "${artifact_path}" && ! -L "${artifact_path}" ]] || {
    printf 'manifest artifact is missing or is a symlink: %s\n' "${relative_path}" >&2
    exit 1
  }
  actual_hash="$(sha256sum "${artifact_path}" | awk '{print $1}')"
  [[ "${actual_hash}" == "${expected_hash}" ]] || {
    printf 'runtime artifact hash mismatch: %s\n' "${relative_path}" >&2
    exit 1
  }
  manifest_paths["${relative_path}"]=1
done < "${manifest}"

[[ ${line_number} -gt 0 ]] || {
  printf '%s\n' 'runtime artifact manifest is empty' >&2
  exit 1
}

artifact_list="$(mktemp)"
trap 'rm -f "${artifact_list}"' EXIT
find -P "${runtime_dir}" -type f -print0 > "${artifact_list}" || {
  printf '%s\n' 'could not inventory runtime artifacts' >&2
  exit 1
}

while IFS= read -r -d '' artifact_path; do
  relative_path="${artifact_path#${runtime_dir}/}"
  case "${relative_path}" in
    runtime.manifest|runtime.manifest.sig)
      continue
      ;;
  esac
  [[ -n "${manifest_paths[${relative_path}]:-}" ]] || {
    printf 'unmanifested runtime artifact: %s\n' "${relative_path}" >&2
    exit 1
  }
done < "${artifact_list}"

printf '%s\n' 'runtime artifact manifest verified'
