#!/usr/bin/env bash
set -euo pipefail

DATA_CENTER_ID="${DATA_CENTER_ID:-EU-RO-1}"
default_volume_suffix="$(printf '%s' "$DATA_CENTER_ID" | tr '[:upper:]' '[:lower:]')"
VOLUME_NAME="${VOLUME_NAME:-kimi-k26-${default_volume_suffix}}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-1000}"
DRY_RUN="${DRY_RUN:-0}"

if ! command -v runpodctl >/dev/null 2>&1; then
  echo "Missing required command: runpodctl" >&2
  exit 1
fi

cat >&2 <<EOF
Creating a billable RunPod network volume.
  name:        ${VOLUME_NAME}
  datacenter:  ${DATA_CENTER_ID}
  size:        ${VOLUME_SIZE_GB} GB

Network volumes persist after pods terminate. Delete the volume when cached
model weights are no longer useful.
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN=1, not creating network volume." >&2
  exit 0
fi

runpodctl network-volume create \
  --name "$VOLUME_NAME" \
  --data-center-id "$DATA_CENTER_ID" \
  --size "$VOLUME_SIZE_GB" \
  --output json
