#!/usr/bin/env bash
set -euo pipefail

HF_MODEL="${HF_MODEL:-unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-30000}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-4096}"
GPU_LAYERS="${GPU_LAYERS:-999}"
PARALLEL="${PARALLEL:-1}"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/workspace/src/llama.cpp}"
LLAMA_CACHE="${LLAMA_CACHE:-/workspace/llama-cache}"
CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES:-80;86;90;100;120}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

export LLAMA_CACHE
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LLAMA_CPP_DIR")" "$LLAMA_CACHE"

if ! command -v git >/dev/null 2>&1 || ! command -v cmake >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    libcurl4-openssl-dev \
    ca-certificates
fi

if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_CPP_DIR"
fi

cd "$LLAMA_CPP_DIR"
cmake -B build \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES"
cmake --build build --config Release -j"$BUILD_THREADS" --target llama-server

exec ./build/bin/llama-server \
  -hf "$HF_MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  -c "$CONTEXT_LENGTH" \
  -ngl "$GPU_LAYERS" \
  --jinja \
  --parallel "$PARALLEL"
