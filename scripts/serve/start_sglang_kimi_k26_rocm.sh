#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-moonshotai/Kimi-K2.6}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-30000}"
TP_SIZE="${TP_SIZE:-4}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-128000}"
KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.8}"
PRE_START_CMD="${PRE_START_CMD:-}"

export HF_HOME="${HF_HOME:-/workspace/hf}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"

mkdir -p "$HF_HOME" /workspace/results

echo "Starting SGLang for ${MODEL_PATH}"
echo "TP=${TP_SIZE} context=${CONTEXT_LENGTH} kv-cache=${KV_CACHE_DTYPE} mem-fraction-static=${MEM_FRACTION_STATIC}"

if [[ -n "$PRE_START_CMD" ]]; then
  echo "Running PRE_START_CMD before SGLang."
  bash -lc "$PRE_START_CMD"
fi

sglang serve \
  --model-path "$MODEL_PATH" \
  --tp "$TP_SIZE" \
  --trust-remote-code \
  --reasoning-parser kimi_k2 \
  --tool-call-parser kimi_k2 \
  --host "$HOST" \
  --port "$PORT" \
  --context-length "$CONTEXT_LENGTH" \
  --kv-cache-dtype "$KV_CACHE_DTYPE" \
  --mem-fraction-static "$MEM_FRACTION_STATIC"
