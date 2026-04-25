#!/usr/bin/env bash
set -euo pipefail

HF_MODEL="${HF_MODEL:-unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-30000}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-2048}"
GPU_LAYERS="${GPU_LAYERS:-999}"
PARALLEL="${PARALLEL:-1}"
TENSOR_SPLIT="${TENSOR_SPLIT:-1,1}"
LLAMA_CACHE="${LLAMA_CACHE:-/workspace/llama-cache}"
ROCR_VISIBLE_DEVICES="${ROCR_VISIBLE_DEVICES:-0,1}"

export LLAMA_CACHE
export ROCR_VISIBLE_DEVICES

mkdir -p "$LLAMA_CACHE"

if ! command -v llama-server >/dev/null 2>&1; then
  for candidate_dir in /opt/rocm/llama.cpp/bin /app /usr/local/bin /usr/bin; do
    if [[ -x "$candidate_dir/llama-server" ]]; then
      export PATH="$candidate_dir:$PATH"
      break
    fi
  done
fi

command -v llama-server >/dev/null 2>&1

exec llama-server \
  -hf "$HF_MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  -c "$CONTEXT_LENGTH" \
  -ngl "$GPU_LAYERS" \
  --parallel "$PARALLEL" \
  --jinja \
  --split-mode layer \
  --tensor-split "$TENSOR_SPLIT" \
  --cache-type-k q8_0 \
  --cache-type-v q8_0
