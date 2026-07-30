#!/usr/bin/env bash
set -Eeuo pipefail

# step-ca's request logger emits the one-time token as `ott`. Redact it before
# stdout reaches Docker's awslogs driver. Cover both the text logger used by
# some releases and the JSON logger configured for the runtime.
sed -E \
  -e 's/(ott=)[^[:space:]]+/\1[REDACTED]/g' \
  -e 's/("ott"[[:space:]]*:[[:space:]]*")[^"]*/\1[REDACTED]/g' \
  -e 's/(token=)[^[:space:]]+/\1[REDACTED]/g' \
  -e 's/("token"[[:space:]]*:[[:space:]]*")[^"]*/\1[REDACTED]/g'
