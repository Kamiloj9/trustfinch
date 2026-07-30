#!/usr/bin/env bash
set -Eeuo pipefail

# Keep step-ca as a child so SIGTERM from Docker Compose is forwarded to the
# CA, while every stdout/stderr line is redacted before Docker persists it.
step_ca_pid=""

stop_step_ca() {
  if [[ -n "${step_ca_pid}" ]]; then
    kill -TERM "${step_ca_pid}" 2>/dev/null || true
    wait "${step_ca_pid}" || true
  fi
  exit 0
}
trap stop_step_ca INT TERM

/usr/local/bin/step-ca "$@" > >(/usr/bin/env bash /usr/local/bin/pki-redact-step-ca-logs) 2>&1 &
step_ca_pid="$!"
wait "${step_ca_pid}"
