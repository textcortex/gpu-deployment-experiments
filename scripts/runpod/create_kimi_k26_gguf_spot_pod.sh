#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
start_script="$repo_root/scripts/serve/start_llamacpp_kimi_k26_gguf_cuda.sh"

: "${GPU_TYPE_ID:=NVIDIA A40}"
: "${GPU_COUNT:=8}"
: "${CLOUD_TYPE:=SECURE}"
: "${DATA_CENTER_ID:=EU-SE-1}"
: "${BID_PER_GPU:=0.37}"
: "${ALLOW_POD_VOLUME:=1}"
: "${VOLUME_GB:=500}"
: "${IMAGE_NAME:=runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404}"
: "${MIN_MEMORY_GB:=128}"
: "${CONTAINER_DISK_GB:=120}"
: "${PORTS:=30000/http,22/tcp}"
: "${NAME:=kimi-k26-gguf-q2-$(date -u +%Y%m%d-%H%M%S)}"
: "${LLAMA_CACHE:=/workspace/llama-cache}"

start_script_body="$(<"$start_script")"

CUSTOM_START_CMD="$(
  printf "cat > /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh <<'SCRIPT'\n%s\nSCRIPT\nchmod +x /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh\nexec /workspace/start_llamacpp_kimi_k26_gguf_cuda.sh" "$start_script_body"
)"

export GPU_TYPE_ID
export GPU_COUNT
export CLOUD_TYPE
export DATA_CENTER_ID
export BID_PER_GPU
export ALLOW_POD_VOLUME
export VOLUME_GB
export IMAGE_NAME
export MIN_MEMORY_GB
export CONTAINER_DISK_GB
export PORTS
export NAME
export LLAMA_CACHE
export CUSTOM_START_CMD

exec "$script_dir/create_spot_pod_graphql.sh"
