#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:?Set BASE_URL, for example http://host:30000/v1}"
MODEL="${MODEL:-moonshotai/Kimi-K2.6}"
REQUESTS="${REQUESTS:-16}"
CONCURRENCY="${CONCURRENCY:-4}"
MAX_TOKENS="${MAX_TOKENS:-1024}"
OUTPUT="${OUTPUT:-results/benchmark-$(date -u +%Y%m%d-%H%M%S).jsonl}"

python scripts/benchmark/benchmark_openai.py \
  --base-url "$BASE_URL" \
  --model "$MODEL" \
  --requests "$REQUESTS" \
  --concurrency "$CONCURRENCY" \
  --max-tokens "$MAX_TOKENS" \
  --output "$OUTPUT"

