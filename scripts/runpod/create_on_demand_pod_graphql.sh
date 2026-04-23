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

: "${NAME:=runpod-on-demand-$(date -u +%Y%m%d-%H%M%S)}"
: "${CLOUD_TYPE:=COMMUNITY}"
: "${GPU_TYPE_ID:=NVIDIA H100 80GB HBM3}"
: "${GPU_COUNT:=5}"
: "${DATA_CENTER_ID:=AP-IN-1}"
: "${IMAGE_NAME:=runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404}"
: "${CONTAINER_DISK_GB:=120}"
: "${VOLUME_GB:=100}"
: "${VOLUME_MOUNT_PATH:=/workspace}"
: "${PORTS:=30000/http,22/tcp}"
: "${CUSTOM_START_CMD:=sleep infinity}"
: "${MIN_VCPU_COUNT:=16}"
: "${MIN_MEMORY_GB:=128}"
: "${DRY_RUN:=0}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require curl
require jq

docker_args="bash -lc $(printf '%s' "$CUSTOM_START_CMD" | jq -Rsr @sh)"

env_json="$(
  jq -n \
    --arg hf_home "${HF_HOME:-/workspace/hf}" \
    --arg hf_transfer "${HF_HUB_ENABLE_HF_TRANSFER:-1}" \
    --arg llama_cache "${LLAMA_CACHE:-/workspace/llama-cache}" \
    '[{key:"HF_HOME", value:$hf_home}, {key:"HF_HUB_ENABLE_HF_TRANSFER", value:$hf_transfer}, {key:"LLAMA_CACHE", value:$llama_cache}]'
)"

if [[ -n "${HF_TOKEN:-}" ]]; then
  env_json="$(jq --arg token "$HF_TOKEN" '. + [{key:"HF_TOKEN", value:$token}]' <<<"$env_json")"
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
    --arg volume_mount_path "$VOLUME_MOUNT_PATH" \
    --argjson volume_gb "$VOLUME_GB" \
    --argjson gpu_count "$GPU_COUNT" \
    --argjson container_disk "$CONTAINER_DISK_GB" \
    --argjson min_vcpu "$MIN_VCPU_COUNT" \
    --argjson min_memory "$MIN_MEMORY_GB" \
    --argjson env "$env_json" '
      {
        query: "mutation($input: PodFindAndDeployOnDemandInput) { podFindAndDeployOnDemand(input: $input) { id imageName machineId costPerHr desiredStatus machine { podHostId dataCenterId gpuDisplayName currentPricePerGpu } } }",
        variables: {
          input: {
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
            volumeInGb: $volume_gb,
            supportPublicIp: true,
            dataCenterId: $data_center,
            startSsh: true,
            env: $env
          }
        }
      }
    '
)"

cat >&2 <<EOF
Creating RunPod on-demand pod via GraphQL.
  name:        ${NAME}
  gpu:         ${GPU_TYPE_ID}
  gpu count:   ${GPU_COUNT}
  cloud:       ${CLOUD_TYPE}
  datacenter:  ${DATA_CENTER_ID}
  image:       ${IMAGE_NAME}
  volume GB:   ${VOLUME_GB}
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

jq 'del(.data.podFindAndDeployOnDemand.env)' <<<"$response"

if jq -e '.errors | length > 0' >/dev/null 2>&1 <<<"$response"; then
  exit 1
fi
