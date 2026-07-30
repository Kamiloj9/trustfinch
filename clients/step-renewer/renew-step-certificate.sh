#!/usr/bin/env bash
set -Eeuo pipefail

# Renew a workload certificate without ever replacing the live file with a
# partial or unverified response. The caller supplies all paths through an
# EnvironmentFile so no private key, CA token, or certificate data is logged.
umask 077

certificate_path="${PKI_CERTIFICATE_PATH:?PKI_CERTIFICATE_PATH is required}"
private_key_path="${PKI_PRIVATE_KEY_PATH:?PKI_PRIVATE_KEY_PATH is required}"
ca_url="${PKI_CA_URL:?PKI_CA_URL is required}"
root_certificate_path="${PKI_ROOT_CERTIFICATE_PATH:?PKI_ROOT_CERTIFICATE_PATH is required}"
renew_expires_in="${PKI_RENEW_EXPIRES_IN:-8h}"
force_now="${PKI_RENEW_FORCE_NOW:-false}"
max_attempts="${PKI_RENEW_MAX_ATTEMPTS:-5}"
backoff_seconds="${PKI_RENEW_BACKOFF_INITIAL_SECONDS:-5}"
max_backoff_seconds="${PKI_RENEW_BACKOFF_MAX_SECONDS:-300}"

for value_name in max_attempts backoff_seconds max_backoff_seconds; do
  value="${!value_name}"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || {
    printf '%s\n' "${value_name} must be a positive integer" >&2
    exit 2
  }
done

case "${force_now}" in
  true|false) ;;
  *)
    printf '%s\n' "PKI_RENEW_FORCE_NOW must be true or false" >&2
    exit 2
    ;;
esac

[[ -r "${certificate_path}" ]] || {
  printf '%s\n' "certificate is not readable" >&2
  exit 2
}
[[ -r "${private_key_path}" ]] || {
  printf '%s\n' "private key is not readable" >&2
  exit 2
}
[[ -r "${root_certificate_path}" ]] || {
  printf '%s\n' "root certificate is not readable" >&2
  exit 2
}

certificate_directory="$(dirname "${certificate_path}")"
certificate_name="$(basename "${certificate_path}")"
certificate_mode="$(stat -c '%a' "${certificate_path}")"
temporary_certificate="$(mktemp "${certificate_directory}/.${certificate_name}.renew.XXXXXX")"

renew_arguments=(
  --force
  --out "${temporary_certificate}"
  --ca-url "${ca_url}"
  --root "${root_certificate_path}"
)
if [[ "${force_now}" == "false" ]]; then
  renew_arguments+=(--expires-in "${renew_expires_in}")
fi

cleanup() {
  rm -f "${temporary_certificate}"
}
trap cleanup EXIT

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  rm -f "${temporary_certificate}"

  if step ca renew "${renew_arguments[@]}" "${certificate_path}" "${private_key_path}"; then
    # A successful command with no output means the existing certificate is
    # still outside the renewal window. It is a safe no-op, not a failure.
    if [[ ! -s "${temporary_certificate}" ]]; then
      exit 0
    fi

    step certificate verify --roots "${root_certificate_path}" "${temporary_certificate}"
    chmod "${certificate_mode}" "${temporary_certificate}"
    mv -f "${temporary_certificate}" "${certificate_path}"

    if [[ -n "${PKI_RELOAD_COMMAND:-}" ]]; then
      /usr/bin/env bash -c "${PKI_RELOAD_COMMAND}"
    fi
    exit 0
  fi

  if (( attempt == max_attempts )); then
    break
  fi

  printf '%s\n' "certificate renewal attempt ${attempt}/${max_attempts} failed; retrying" >&2
  sleep "${backoff_seconds}"
  backoff_seconds=$((backoff_seconds * 2))
  if (( backoff_seconds > max_backoff_seconds )); then
    backoff_seconds="${max_backoff_seconds}"
  fi
done

printf '%s\n' "certificate renewal failed after ${max_attempts} attempts" >&2
exit 1
