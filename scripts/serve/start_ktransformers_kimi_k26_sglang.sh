#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-/workspace/models/kimi-k2.6}"
KT_WEIGHT_PATH="${KT_WEIGHT_PATH:-$MODEL_PATH}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-31245}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-Kimi-K2.6}"
TP_SIZE="${TP_SIZE:-4}"
KT_CPUINFER="${KT_CPUINFER:-96}"
KT_THREADPOOL_COUNT="${KT_THREADPOOL_COUNT:-2}"
KT_NUM_GPU_EXPERTS="${KT_NUM_GPU_EXPERTS:-30}"
KT_METHOD="${KT_METHOD:-RAWINT4}"
KT_GPU_PREFILL_TOKEN_THRESHOLD="${KT_GPU_PREFILL_TOKEN_THRESHOLD:-400}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.94}"
CHUNKED_PREFILL_SIZE="${CHUNKED_PREFILL_SIZE:-32658}"
MAX_TOTAL_TOKENS="${MAX_TOTAL_TOKENS:-50000}"
MAX_RUNNING_REQUESTS="${MAX_RUNNING_REQUESTS:-}"
ATTENTION_BACKEND="${ATTENTION_BACKEND:-flashinfer}"
KT_ENABLE_DYNAMIC_EXPERT_UPDATE="${KT_ENABLE_DYNAMIC_EXPERT_UPDATE:-0}"
KT_EXPERT_PLACEMENT_STRATEGY="${KT_EXPERT_PLACEMENT_STRATEGY:-}"
KT_MAX_DEFERRED_EXPERTS_PER_TOKEN="${KT_MAX_DEFERRED_EXPERTS_PER_TOKEN:-}"
DISABLE_SHARED_EXPERTS_FUSION="${DISABLE_SHARED_EXPERTS_FUSION:-1}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-}"
PRE_START_CMD="${PRE_START_CMD:-}"
DISABLE_CUDA_GRAPH="${DISABLE_CUDA_GRAPH:-0}"

if [[ ! -d "$MODEL_PATH" ]]; then
  echo "MODEL_PATH does not exist: $MODEL_PATH" >&2
  exit 1
fi

if [[ -n "$PRE_START_CMD" ]]; then
  echo "Running PRE_START_CMD before launch."
  bash -lc "$PRE_START_CMD"
fi

echo "Starting KTransformers + SGLang for ${MODEL_PATH}"
echo "host=${HOST} port=${PORT} tp=${TP_SIZE} cpuinfer=${KT_CPUINFER} gpu_experts=${KT_NUM_GPU_EXPERTS}"

args=(
  --host "$HOST"
  --port "$PORT"
  --model "$MODEL_PATH"
  --kt-weight-path "$KT_WEIGHT_PATH"
  --kt-cpuinfer "$KT_CPUINFER"
  --kt-threadpool-count "$KT_THREADPOOL_COUNT"
  --kt-num-gpu-experts "$KT_NUM_GPU_EXPERTS"
  --kt-method "$KT_METHOD"
  --kt-gpu-prefill-token-threshold "$KT_GPU_PREFILL_TOKEN_THRESHOLD"
  --trust-remote-code
  --mem-fraction-static "$MEM_FRACTION_STATIC"
  --served-model-name "$SERVED_MODEL_NAME"
  --enable-mixed-chunk
  --tensor-parallel-size "$TP_SIZE"
  --enable-p2p-check
  --chunked-prefill-size "$CHUNKED_PREFILL_SIZE"
  --max-total-tokens "$MAX_TOTAL_TOKENS"
  --attention-backend "$ATTENTION_BACKEND"
)

if [[ -n "$MAX_RUNNING_REQUESTS" ]]; then
  args+=(--max-running-requests "$MAX_RUNNING_REQUESTS")
fi

if [[ "$KT_ENABLE_DYNAMIC_EXPERT_UPDATE" == "1" ]]; then
  args+=(--kt-enable-dynamic-expert-update)
fi

if [[ -n "$KT_EXPERT_PLACEMENT_STRATEGY" ]]; then
  args+=(--kt-expert-placement-strategy "$KT_EXPERT_PLACEMENT_STRATEGY")
fi

if [[ -n "$KT_MAX_DEFERRED_EXPERTS_PER_TOKEN" ]]; then
  args+=(--kt-max-deferred-experts-per-token "$KT_MAX_DEFERRED_EXPERTS_PER_TOKEN")
fi

if [[ "$DISABLE_SHARED_EXPERTS_FUSION" == "1" ]]; then
  args+=(--disable-shared-experts-fusion)
fi

if [[ -n "$WATCHDOG_TIMEOUT" ]]; then
  args+=(--watchdog-timeout "$WATCHDOG_TIMEOUT")
fi

if [[ "$DISABLE_CUDA_GRAPH" == "1" ]]; then
  args+=(--disable-cuda-graph)
fi

exec python -m sglang.launch_server "${args[@]}"
