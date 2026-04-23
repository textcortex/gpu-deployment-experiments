#!/usr/bin/env bash
set -euo pipefail

: "${RUNPOD_API_KEY:?Set RUNPOD_API_KEY in your environment. Do not commit it.}"

NAME="${NAME:-kimi-k26-mi300x-$(date -u +%Y%m%d-%H%M%S)}"
GPU_TYPE_ID="${GPU_TYPE_ID:-AMD Instinct MI300X OAM}"
GPU_COUNT="${GPU_COUNT:-4}"
DATA_CENTER_IDS="${DATA_CENTER_IDS:-${DATA_CENTER_ID:-EU-RO-1}}"
IMAGE_NAME="${IMAGE_NAME:-lmsysorg/sglang:v0.5.9-rocm700-mi30x}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-120}"
VOLUME_GB="${VOLUME_GB:-1000}"
VOLUME_MOUNT_PATH="${VOLUME_MOUNT_PATH:-/workspace}"
NETWORK_VOLUME_ID="${NETWORK_VOLUME_ID:-}"
ALLOW_POD_VOLUME="${ALLOW_POD_VOLUME:-0}"
PORTS="${PORTS:-30000/http,22/tcp}"
START_SERVER="${START_SERVER:-1}"
TP_SIZE="${TP_SIZE:-${GPU_COUNT}}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-128000}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.8}"
KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
MODEL_PATH="${MODEL_PATH:-moonshotai/Kimi-K2.6}"
PRE_START_CMD="${PRE_START_CMD:-}"
DRY_RUN="${DRY_RUN:-0}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require curl
require jq

if [[ -z "$NETWORK_VOLUME_ID" && "$ALLOW_POD_VOLUME" != "1" ]]; then
  cat >&2 <<EOF
NETWORK_VOLUME_ID is required by default so model weights persist on cheaper,
portable RunPod network storage.

Create one with scripts/runpod/create_network_volume.sh, then rerun with:
  NETWORK_VOLUME_ID=<volume-id> $0

For a disposable test without a network volume, set ALLOW_POD_VOLUME=1.
EOF
  exit 1
fi

ports_json="$(
  jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))' <<<"$PORTS"
)"

datacenters_json="$(
  jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))' <<<"$DATA_CENTER_IDS"
)"

pod_env="$(
  jq -n \
    --arg hf_home "${HF_HOME:-/workspace/hf}" \
    --arg hf_transfer "${HF_HUB_ENABLE_HF_TRANSFER:-1}" \
    '{HF_HOME: $hf_home, HF_HUB_ENABLE_HF_TRANSFER: $hf_transfer}'
)"

if [[ -n "${HF_TOKEN:-}" ]]; then
  pod_env="$(jq --arg token "$HF_TOKEN" '. + {HF_TOKEN: $token}' <<<"$pod_env")"
fi

if [[ "${START_SERVER}" == "1" ]]; then
  prelude=""
  if [[ -n "$PRE_START_CMD" ]]; then
    prelude="${PRE_START_CMD} && "
  fi
  start_cmd="$(
    cat <<EOF
mkdir -p /workspace/hf /workspace/results && \
${prelude}\
sglang serve \
  --model-path ${MODEL_PATH} \
  --tp ${TP_SIZE} \
  --trust-remote-code \
  --reasoning-parser kimi_k2 \
  --tool-call-parser kimi_k2 \
  --host 0.0.0.0 \
  --port 30000 \
  --context-length ${CONTEXT_LENGTH} \
  --kv-cache-dtype ${KV_CACHE_DTYPE} \
  --mem-fraction-static ${MEM_FRACTION_STATIC}
EOF
  )"
else
  start_cmd="sleep infinity"
fi

payload="$(
  jq -n \
    --arg name "$NAME" \
    --arg image "$IMAGE_NAME" \
    --arg gpu "$GPU_TYPE_ID" \
    --argjson gpu_count "$GPU_COUNT" \
    --argjson datacenters "$datacenters_json" \
    --argjson ports "$ports_json" \
    --argjson env "$pod_env" \
    --argjson container_disk "$CONTAINER_DISK_GB" \
    --argjson volume_gb "$VOLUME_GB" \
    --arg volume_mount_path "$VOLUME_MOUNT_PATH" \
    --arg network_volume_id "$NETWORK_VOLUME_ID" \
    --arg start_cmd "$start_cmd" '
      {
        name: $name,
        cloudType: "SECURE",
        computeType: "GPU",
        imageName: $image,
        interruptible: true,
        gpuTypeIds: [$gpu],
        gpuTypePriority: "custom",
        gpuCount: $gpu_count,
        dataCenterIds: $datacenters,
        dataCenterPriority: "custom",
        containerDiskInGb: $container_disk,
        volumeMountPath: $volume_mount_path,
        ports: $ports,
        env: $env,
        dockerEntrypoint: ["bash", "-lc"],
        dockerStartCmd: [$start_cmd],
        supportPublicIp: true
      }
      + (
        if $network_volume_id == "" then
          {volumeInGb: $volume_gb}
        else
          {networkVolumeId: $network_volume_id}
        end
      )
    '
)"

cat >&2 <<EOF
Creating RunPod spot pod via REST API.
  name:        ${NAME}
  gpu:         ${GPU_TYPE_ID}
  gpu count:   ${GPU_COUNT}
  datacenters: ${DATA_CENTER_IDS}
  image:       ${IMAGE_NAME}
  spot:        true
  network vol: ${NETWORK_VOLUME_ID:-none}
  start server:${START_SERVER}
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN=1, not creating pod. Sanitized payload:" >&2
  jq 'del(.env.HF_TOKEN)' <<<"$payload"
  exit 0
fi

response="$(
  curl --fail-with-body --silent --show-error \
    --request POST \
    --url "https://rest.runpod.io/v1/pods" \
    --header "Authorization: Bearer ${RUNPOD_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "$payload"
)"

# Do not echo env back to the terminal; it may include HF_TOKEN.
jq 'del(.env)' <<<"$response"
