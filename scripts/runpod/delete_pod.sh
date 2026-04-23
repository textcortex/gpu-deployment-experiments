#!/usr/bin/env bash
set -euo pipefail

: "${RUNPOD_API_KEY:?Set RUNPOD_API_KEY in your environment. Do not commit it.}"

POD_ID="${1:-${RUNPOD_POD_ID:-}}"
if [[ -z "$POD_ID" ]]; then
  echo "Usage: $0 POD_ID" >&2
  exit 1
fi

curl --fail-with-body --silent --show-error \
  --request DELETE \
  --url "https://rest.runpod.io/v1/pods/${POD_ID}" \
  --header "Authorization: Bearer ${RUNPOD_API_KEY}" |
  jq 'del(.env)'

