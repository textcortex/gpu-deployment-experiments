#!/usr/bin/env bash
set -euo pipefail

CONFIG_NAME="${CONFIG_NAME:?CONFIG_NAME is required}"
MODEL_PATH="${MODEL_PATH:-/workspace/models/kimi-k2.6}"
PORT="${PORT:-31245}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
RESULTS_DIR="${RESULTS_DIR:-/workspace/results}"
REPO_DIR="${REPO_DIR:-/workspace/gpu-deployment-experiments}"
SOURCE_DIR="${SOURCE_DIR:-/workspace/src/ktransformers-v053}"
VENV_PATH="${VENV_PATH:-/workspace/venv053}"
PROMPT_FILE="${PROMPT_FILE:-$REPO_DIR/scripts/benchmark/prompts/kimi_throughput_short.txt}"
BENCH_REQUESTS="${BENCH_REQUESTS:-8}"
BENCH_CONCURRENCY="${BENCH_CONCURRENCY:-4}"
BENCH_MAX_TOKENS="${BENCH_MAX_TOKENS:-64}"
SMOKE_MAX_TOKENS="${SMOKE_MAX_TOKENS:-64}"
WAIT_TIMEOUT_SECS="${WAIT_TIMEOUT_SECS:-1200}"
POST_READY_SLEEP_SECS="${POST_READY_SLEEP_SECS:-90}"
BASE_URL="http://127.0.0.1:${PORT}/v1"
SERVER_LOG="${LOG_DIR}/${CONFIG_NAME}.log"
BENCH_OUTPUT="${RESULTS_DIR}/${CONFIG_NAME}.jsonl"

mkdir -p "$LOG_DIR" "$RESULTS_DIR"

source "${VENV_PATH}/bin/activate"
export PYTHONPATH="${SOURCE_DIR}:${PYTHONPATH:-}"

pkill -f 'python -m sglang.launch_server' || true
pkill -f 'sglang::scheduler' || true
pkill -f nvcc || true
pkill -f ptxas || true
sleep 2

rm -f "$SERVER_LOG"
cd "$SOURCE_DIR"
nohup env MODEL_PATH="$MODEL_PATH" KT_WEIGHT_PATH="$MODEL_PATH" \
  "$REPO_DIR/scripts/serve/start_ktransformers_kimi_k26_sglang.sh" \
  >"$SERVER_LOG" 2>&1 < /dev/null &

deadline=$((SECONDS + WAIT_TIMEOUT_SECS))
until curl -fsS "${BASE_URL}/models" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for ${BASE_URL}/models" >&2
    tail -n 200 "$SERVER_LOG" >&2 || true
    exit 1
  fi
  sleep 5
done

if (( POST_READY_SLEEP_SECS > 0 )); then
  echo "Endpoint is up; waiting ${POST_READY_SLEEP_SECS}s for generation readiness."
  sleep "$POST_READY_SLEEP_SECS"
fi

python "$REPO_DIR/scripts/benchmark/smoke_openai.py" \
  --base-url "$BASE_URL" \
  --model Kimi-K2.6 \
  --instant \
  --max-tokens "$SMOKE_MAX_TOKENS"

python "$REPO_DIR/scripts/benchmark/benchmark_openai.py" \
  --base-url "$BASE_URL" \
  --model Kimi-K2.6 \
  --instant \
  --requests "$BENCH_REQUESTS" \
  --concurrency "$BENCH_CONCURRENCY" \
  --max-tokens "$BENCH_MAX_TOKENS" \
  --prompt-file "$PROMPT_FILE" \
  --output "$BENCH_OUTPUT"
