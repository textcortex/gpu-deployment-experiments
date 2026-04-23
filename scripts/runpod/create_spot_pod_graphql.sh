#!/usr/bin/env bash
set -euo pipefail

api_key_from_config() {
  if [[ -f "$HOME/.runpod/config.toml" ]]; then
    sed -n "s/^apikey[[:space:]]*=[[:space:]]*//p" "$HOME/.runpod/config.toml" |
      sed "s/^[[:space:]'\\\"]*//; s/[[:space:]'\\\"]*$//" |
      head -n 1
  fi
}

RUNPOD_API_KEY="${RUNPOD_API_KEY:-$(api_key_from_config)}"
: "${RUNPOD_API_KEY:?Set RUNPOD_API_KEY or run runpodctl doctor first.}"

NAME="${NAME:-kimi-k26-mi300x-$(date -u +%Y%m%d-%H%M%S)}"
CLOUD_TYPE="${CLOUD_TYPE:-SECURE}"
GPU_TYPE_ID="${GPU_TYPE_ID:-AMD Instinct MI300X OAM}"
GPU_COUNT="${GPU_COUNT:-4}"
DATA_CENTER_ID="${DATA_CENTER_ID:-EU-RO-1}"
IMAGE_NAME="${IMAGE_NAME:-lmsysorg/sglang:v0.5.9-rocm700-mi30x}"
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-120}"
VOLUME_GB="${VOLUME_GB:-1000}"
VOLUME_MOUNT_PATH="${VOLUME_MOUNT_PATH:-/workspace}"
NETWORK_VOLUME_ID="${NETWORK_VOLUME_ID:-}"
ALLOW_POD_VOLUME="${ALLOW_POD_VOLUME:-0}"
PORTS="${PORTS:-30000/http,22/tcp}"
BID_PER_GPU="${BID_PER_GPU:-1.69}"
START_SERVER="${START_SERVER:-1}"
TP_SIZE="${TP_SIZE:-${GPU_COUNT}}"
PP_SIZE="${PP_SIZE:-1}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-128000}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.8}"
KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
MODEL_PATH="${MODEL_PATH:-moonshotai/Kimi-K2.6}"
PRE_START_CMD="${PRE_START_CMD:-uv pip install \"sglang>=0.5.10.post1\" --prerelease=allow}"
CPU_OFFLOAD_GB="${CPU_OFFLOAD_GB:-0}"
CUSTOM_START_CMD="${CUSTOM_START_CMD:-}"
CUSTOM_DOCKER_ARGS="${CUSTOM_DOCKER_ARGS:-}"
MIN_VCPU_COUNT="${MIN_VCPU_COUNT:-32}"
MIN_MEMORY_GB="${MIN_MEMORY_GB:-128}"
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
NETWORK_VOLUME_ID is required by default so model weights persist on portable
RunPod network storage.

Set NETWORK_VOLUME_ID=<volume-id>, or set ALLOW_POD_VOLUME=1 for a disposable
capacity probe using a normal pod volume.
EOF
  exit 1
fi

if [[ -n "$CUSTOM_START_CMD" ]]; then
  server_cmd="$CUSTOM_START_CMD"
elif [[ "$START_SERVER" == "1" ]]; then
  server_cmd="mkdir -p /workspace/hf /workspace/results"
  if [[ -n "$PRE_START_CMD" ]]; then
    server_cmd="${server_cmd} && ${PRE_START_CMD}"
  fi
  server_cmd="${server_cmd} && sglang serve --model-path ${MODEL_PATH} --tp ${TP_SIZE} --trust-remote-code --reasoning-parser kimi_k2 --tool-call-parser kimi_k2 --host 0.0.0.0 --port 30000 --context-length ${CONTEXT_LENGTH} --kv-cache-dtype ${KV_CACHE_DTYPE} --mem-fraction-static ${MEM_FRACTION_STATIC}"
  if [[ "$PP_SIZE" != "1" ]]; then
    server_cmd="${server_cmd} --pipeline-parallel-size ${PP_SIZE}"
  fi
  if [[ "$CPU_OFFLOAD_GB" != "0" ]]; then
    server_cmd="${server_cmd} --cpu-offload-gb ${CPU_OFFLOAD_GB}"
  fi
else
  server_cmd="sleep infinity"
fi

if [[ -n "$CUSTOM_DOCKER_ARGS" ]]; then
  docker_args="$CUSTOM_DOCKER_ARGS"
else
  docker_args="bash -lc $(printf '%s' "$server_cmd" | jq -Rsr @sh)"
fi

env_json="$(
  jq -n \
    --arg hf_home "${HF_HOME:-/workspace/hf}" \
    --arg hf_transfer "${HF_HUB_ENABLE_HF_TRANSFER:-1}" \
    '[{key:"HF_HOME", value:$hf_home}, {key:"HF_HUB_ENABLE_HF_TRANSFER", value:$hf_transfer}]'
)"

if [[ -n "${HF_TOKEN:-}" ]]; then
  env_json="$(jq --arg token "$HF_TOKEN" '. + [{key:"HF_TOKEN", value:$token}]' <<<"$env_json")"
fi

if [[ -n "${LLAMA_CACHE:-}" ]]; then
  env_json="$(jq --arg cache "$LLAMA_CACHE" '. + [{key:"LLAMA_CACHE", value:$cache}]' <<<"$env_json")"
fi

payload="$(
  jq -n \
    --arg name "$NAME" \
    --arg cloud_type "$CLOUD_TYPE" \
    --arg gpu "$GPU_TYPE_ID" \
    --arg data_center "$DATA_CENTER_ID" \
    --arg image "$IMAGE_NAME" \
    --arg docker_args "$docker_args" \
    --arg ports "$PORTS" \
    --arg network_volume_id "$NETWORK_VOLUME_ID" \
    --arg volume_mount_path "$VOLUME_MOUNT_PATH" \
    --argjson volume_gb "$VOLUME_GB" \
    --argjson bid "$BID_PER_GPU" \
    --argjson gpu_count "$GPU_COUNT" \
    --argjson container_disk "$CONTAINER_DISK_GB" \
    --argjson min_vcpu "$MIN_VCPU_COUNT" \
    --argjson min_memory "$MIN_MEMORY_GB" \
    --argjson env "$env_json" '
      {
        query: "mutation($input: PodRentInterruptableInput!) { podRentInterruptable(input: $input) { id imageName machineId machine { podHostId dataCenterId gpuDisplayName currentPricePerGpu } } }",
        variables: {
          input: ({
            bidPerGpu: $bid,
            cloudType: $cloud_type,
            gpuCount: $gpu_count,
            containerDiskInGb: $container_disk,
            minVcpuCount: $min_vcpu,
            minMemoryInGb: $min_memory,
            gpuTypeId: $gpu,
            name: $name,
            imageName: $image,
            dockerArgs: $docker_args,
            ports: $ports,
            volumeMountPath: $volume_mount_path,
            supportPublicIp: true,
            dataCenterId: $data_center,
            startSsh: true,
            env: $env
          }
          + (
            if $network_volume_id == "" then
              {volumeInGb: $volume_gb}
            else
              {networkVolumeId: $network_volume_id}
            end
          ))
        }
      }
    '
)"

cat >&2 <<EOF
Creating RunPod spot pod via GraphQL.
  name:        ${NAME}
  gpu:         ${GPU_TYPE_ID}
  gpu count:   ${GPU_COUNT}
  cloud:       ${CLOUD_TYPE}
  datacenter:  ${DATA_CENTER_ID}
  image:       ${IMAGE_NAME}
  bid/gpu:     ${BID_PER_GPU}
  network vol: ${NETWORK_VOLUME_ID}
  start server:${START_SERVER}
  TP/PP:       ${TP_SIZE}/${PP_SIZE}
  cpu offload: ${CPU_OFFLOAD_GB} GB
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN=1, not creating pod. Sanitized payload:" >&2
  jq 'del(.variables.input.env[] | select(.key == "HF_TOKEN"))' <<<"$payload"
  exit 0
fi

response="$(
  curl --silent --show-error \
    --request POST \
    --header "content-type: application/json" \
    --url "https://api.runpod.io/graphql?api_key=${RUNPOD_API_KEY}" \
    --data "$payload"
)"

jq 'del(.data.podRentInterruptable.env)' <<<"$response"

if jq -e '.errors | length > 0' >/dev/null 2>&1 <<<"$response"; then
  exit 1
fi
