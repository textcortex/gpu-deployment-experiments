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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
start_script="$repo_root/scripts/serve/start_llamacpp_kimi_k26_gguf_cuda.sh"

: "${NAME:=kimi-k26-gguf-q2-$(date -u +%Y%m%d-%H%M%S)}"
: "${CLOUD_TYPE:=COMMUNITY}"
: "${GPU_TYPE_ID:=NVIDIA RTX A6000}"
: "${GPU_COUNT:=8}"
: "${DATA_CENTER_IDS:=${DATA_CENTER_ID:-CA-MTL-3}}"
: "${INTERRUPTIBLE:=false}"
: "${IMAGE_NAME:=runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404}"
: "${CONTAINER_DISK_GB:=120}"
: "${VOLUME_GB:=500}"
: "${VOLUME_MOUNT_PATH:=/workspace}"
: "${PORTS:=30000/http,22/tcp}"
: "${MIN_VCPU_PER_GPU:=2}"
: "${MIN_RAM_PER_GPU:=8}"
: "${CUSTOM_START_CMD:=}"
: "${DRY_RUN:=0}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require curl
require jq

ports_json="$(
  jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))' <<<"$PORTS"
)"

datacenters_json="$(
  jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))' <<<"$DATA_CENTER_IDS"
)"

if [[ -n "$CUSTOM_START_CMD" ]]; then
  start_cmd="$CUSTOM_START_CMD"
else
  start_script_body="$(<"$start_script")"
  start_cmd="$(
    printf "cat > /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh <<'SCRIPT'\n%s\nSCRIPT\nchmod +x /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh\nexec /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh" "$start_script_body"
  )"
fi

pod_env="$(
  jq -n \
    --arg hf_home "${HF_HOME:-/workspace/hf}" \
    --arg hf_transfer "${HF_HUB_ENABLE_HF_TRANSFER:-1}" \
    --arg llama_cache "${LLAMA_CACHE:-/workspace/llama-cache}" \
    '{HF_HOME: $hf_home, HF_HUB_ENABLE_HF_TRANSFER: $hf_transfer, LLAMA_CACHE: $llama_cache}'
)"

if [[ -n "${HF_TOKEN:-}" ]]; then
  pod_env="$(jq --arg token "$HF_TOKEN" '. + {HF_TOKEN: $token}' <<<"$pod_env")"
fi

payload="$(
  jq -n \
    --arg name "$NAME" \
    --arg cloud_type "$CLOUD_TYPE" \
    --arg image "$IMAGE_NAME" \
    --arg gpu "$GPU_TYPE_ID" \
    --argjson gpu_count "$GPU_COUNT" \
    --argjson datacenters "$datacenters_json" \
    --argjson ports "$ports_json" \
    --argjson env "$pod_env" \
    --argjson interruptible "$INTERRUPTIBLE" \
    --argjson container_disk "$CONTAINER_DISK_GB" \
    --argjson volume_gb "$VOLUME_GB" \
    --argjson min_vcpu_per_gpu "$MIN_VCPU_PER_GPU" \
    --argjson min_ram_per_gpu "$MIN_RAM_PER_GPU" \
    --arg volume_mount_path "$VOLUME_MOUNT_PATH" \
    --arg start_cmd "$start_cmd" '
      {
        name: $name,
        cloudType: $cloud_type,
        computeType: "GPU",
        imageName: $image,
        interruptible: $interruptible,
        gpuTypeIds: [$gpu],
        gpuTypePriority: "custom",
        gpuCount: $gpu_count,
        dataCenterIds: $datacenters,
        dataCenterPriority: "custom",
        containerDiskInGb: $container_disk,
        volumeInGb: $volume_gb,
        volumeMountPath: $volume_mount_path,
        minVCPUPerGPU: $min_vcpu_per_gpu,
        minRAMPerGPU: $min_ram_per_gpu,
        ports: $ports,
        env: $env,
        dockerEntrypoint: ["bash", "-lc"],
        dockerStartCmd: [$start_cmd],
        supportPublicIp: true
      }
    '
)"

cat >&2 <<EOF
Creating RunPod pod via REST API.
  name:        ${NAME}
  gpu:         ${GPU_TYPE_ID}
  gpu count:   ${GPU_COUNT}
  cloud:       ${CLOUD_TYPE}
  datacenters: ${DATA_CENTER_IDS}
  image:       ${IMAGE_NAME}
  interrupt:   ${INTERRUPTIBLE}
  volume GB:   ${VOLUME_GB}
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN=1, not creating pod. Sanitized payload:" >&2
  jq 'del(.env.HF_TOKEN)' <<<"$payload"
  exit 0
fi

response_file="$(mktemp)"
status_code="$(
  curl --silent --show-error \
    --request POST \
    --url "https://rest.runpod.io/v1/pods" \
    --header "Authorization: Bearer ${RUNPOD_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    --output "$response_file" \
    --write-out "%{http_code}"
)"
response="$(cat "$response_file")"
rm -f "$response_file"

if [[ "$status_code" -lt 200 || "$status_code" -ge 300 ]]; then
  echo "RunPod create pod failed with HTTP ${status_code}." >&2
  if jq empty >/dev/null 2>&1 <<<"$response"; then
    jq 'if type == "object" then del(.env) else . end' <<<"$response" >&2
  else
    printf '%s\n' "$response" >&2
  fi
  exit 1
fi

jq 'if type == "object" then del(.env) else . end' <<<"$response"
