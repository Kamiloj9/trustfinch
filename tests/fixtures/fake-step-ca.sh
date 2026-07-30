#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'level=info ott=token-value-that-must-not-be-logged status=201'
printf '%s\n' '{"level":"info","ott":"json-token-value-that-must-not-be-logged","status":201}'
