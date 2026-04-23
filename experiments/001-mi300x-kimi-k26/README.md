# Experiment 001: Kimi K2.6 on RunPod AMD MI300X

Status: planned

## Goal

Deploy `moonshotai/Kimi-K2.6` on AMD MI300X spot pods, expose an OpenAI-compatible endpoint, and capture smoke and throughput benchmark results for a reproducible baseline.

## Current Hypothesis

SGLang on 4x MI300X is the best first baseline because the current SGLang Kimi K2.6 cookbook gives AMD-specific settings for MI300X and explains why tensor parallelism should be 4 on AMD for this model.

## Launch Runbook

From the repo root:

```bash
source .env
scripts/runpod/check_availability.sh
```

Create a network volume if one does not already exist in the target datacenter:

```bash
DRY_RUN=1 \
DATA_CENTER_ID=EU-RO-1 \
VOLUME_NAME=kimi-k26-eu-ro-1 \
VOLUME_SIZE_GB=1000 \
scripts/runpod/create_network_volume.sh
```

Create a spot pod:

```bash
DRY_RUN=1 \
NETWORK_VOLUME_ID=<volume-id-from-previous-step> \
DATA_CENTER_IDS=EU-RO-1 \
GPU_COUNT=4 \
scripts/runpod/create_spot_pod_rest.sh
```

Remove `DRY_RUN=1` only when the billable settings look correct.

The pod script requires `NETWORK_VOLUME_ID` by default. Use `ALLOW_POD_VOLUME=1` only for a disposable run where cached weights do not need to survive pod deletion.
For explicit spot bidding through RunPod GraphQL:

```bash
BID_PER_GPU=1.69 \
NETWORK_VOLUME_ID=<volume-id> \
scripts/runpod/create_spot_pod_graphql.sh
```

If startup fails because the image has an older SGLang build, relaunch with:

```bash
PRE_START_CMD='uv pip install "sglang>=0.5.10.post1" --prerelease=allow' \
NETWORK_VOLUME_ID=<volume-id> \
scripts/runpod/create_spot_pod_rest.sh
```

The pod script starts SGLang by default. To create an idle pod for manual inspection instead:

```bash
START_SERVER=0 scripts/runpod/create_spot_pod_rest.sh
```

## Smoke Test

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install openai

python scripts/benchmark/smoke_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "moonshotai/Kimi-K2.6"
```

## Benchmark

```bash
python scripts/benchmark/benchmark_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "moonshotai/Kimi-K2.6" \
  --requests 32 \
  --concurrency 8 \
  --max-tokens 1024 \
  --temperature 1.0 \
  --top-p 0.95 \
  --output results/001-mi300x-kimi-k26-c8.jsonl
```

## Settings to Sweep

| Sweep | Values |
| --- | --- |
| Concurrency | 1, 2, 4, 8, 16, 32 |
| Max tokens | 256, 1024, 4096 |
| Mode | thinking, instant |
| Context length | 64000, 128000, 262144 if memory allows |
| KV cache | default, `fp8_e4m3` |
| `mem-fraction-static` | 0.75, 0.8, 0.85 |
| CPU offload | 0, 64, 128 for 2x MI300X fallback |

## Smaller Fallback Attempt

If 4x MI300X spot capacity is unavailable, try a 2x MI300X CPU-offload probe:

```bash
GPU_COUNT=2 \
TP_SIZE=2 \
CONTEXT_LENGTH=8192 \
CPU_OFFLOAD_GB=128 \
MIN_MEMORY_GB=512 \
BID_PER_GPU=1.99 \
NETWORK_VOLUME_ID=<volume-id> \
scripts/runpod/create_spot_pod_graphql.sh
```

This is expected to be much slower than the 4x baseline and may fail during load if CPU offload is not enough for Kimi K2.6 on MI300X.

For a 3x MI300X probe, do not use `TP_SIZE=3`. Kimi K2.6 has 64 attention heads, so tensor parallelism of 3 is not a clean shard. Use pipeline parallelism instead:

```bash
GPU_COUNT=3 \
TP_SIZE=1 \
PP_SIZE=3 \
CONTEXT_LENGTH=4096 \
CPU_OFFLOAD_GB=64 \
MIN_MEMORY_GB=512 \
BID_PER_GPU=1.99 \
NETWORK_VOLUME_ID=<volume-id> \
scripts/runpod/create_spot_pod_graphql.sh
```

This is also a feasibility probe, not a baseline.

## Stop Condition

Terminate the pod after each benchmark window unless another run starts immediately:

```bash
scripts/runpod/delete_pod.sh POD_ID
```

Network volumes continue billing after pod termination, so delete them when we no longer need cached weights.
