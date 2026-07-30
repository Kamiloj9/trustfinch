#!/usr/bin/env bash
set -Eeuo pipefail

# Keep step-ca as a child so SIGTERM from Docker Compose is forwarded to the
# CA, while every stdout/stderr line is redacted before Docker persists it.
# A FIFO lets the wrapper wait for the redactor to drain after step-ca exits;
# a process substitution can lose the final lines during a fast shutdown.
step_ca_pid=""
redactor_pid=""
log_directory="$(mktemp -d -t pki-step-ca-logs.XXXXXX)"
log_fifo="${log_directory}/step-ca.log"
mkfifo "${log_fifo}"

cleanup_logs() {
  rm -f "${log_fifo}"
  rmdir "${log_directory}" 2>/dev/null || true
}

stop_step_ca() {
  if [[ -n "${step_ca_pid}" ]]; then
    kill -TERM "${step_ca_pid}" 2>/dev/null || true
    wait "${step_ca_pid}" || true
  fi
  if [[ -n "${redactor_pid}" ]]; then
    wait "${redactor_pid}" || true
  fi
  cleanup_logs
  exit 0
}
trap stop_step_ca INT TERM

/usr/bin/env bash /usr/local/bin/pki-redact-step-ca-logs <"${log_fifo}" &
redactor_pid="$!"

/usr/local/bin/step-ca "$@" >"${log_fifo}" 2>&1 &
step_ca_pid="$!"

set +e
wait "${step_ca_pid}"
step_ca_status="$?"
wait "${redactor_pid}"
redactor_status="$?"
set -e

cleanup_logs

if [[ "${step_ca_status}" -ne 0 ]]; then
  exit "${step_ca_status}"
fi

exit "${redactor_status}"
