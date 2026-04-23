#!/usr/bin/env bash
set -euo pipefail

GPU_TYPE_ID="${GPU_TYPE_ID:-AMD Instinct MI300X OAM}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require runpodctl
require jq

echo "GPU availability for: ${GPU_TYPE_ID}"
runpodctl gpu list --output json |
  jq --arg gpu "$GPU_TYPE_ID" '.[] | select(.gpuId == $gpu)'

echo
echo "Datacenters advertising ${GPU_TYPE_ID}:"
runpodctl datacenter list --output json |
  jq --arg gpu "$GPU_TYPE_ID" '
    map(select(.gpuAvailability != null))
    | map({
        id,
        location,
        name,
        gpuAvailability: [
          .gpuAvailability[] | select(.gpuId == $gpu)
        ]
      })
    | map(select(.gpuAvailability | length > 0))
  '

