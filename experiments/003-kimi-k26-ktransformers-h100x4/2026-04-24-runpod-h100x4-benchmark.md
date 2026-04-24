# RunPod Kimi K2.6 Benchmark: 2026-04-24

## Metadata

| Field | Value |
| --- | --- |
| Experiment | `003-kimi-k26-ktransformers-h100x4` |
| Date | 2026-04-24 |
| Operator | Codex |
| Provider | RunPod |
| Datacenter | `AP-IN-1` |
| Pod ID | `u6s9yx2vfu1rzl` |
| GPU type | `NVIDIA H100 80GB HBM3` |
| GPU count | `4` |
| Spot / interruptible | `No` |
| Network volume ID | n/a |
| Container image | `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404` |
| Serving engine | `KTransformers via sglang.launch_server` |
| Model | `moonshotai/Kimi-K2.6` |

## Goal

Validate a real end-to-end Kimi K2.6 deployment on RunPod after repeated MI300X, A40, and custom-image readiness failures, then record the first reproducible performance baseline.

## Configuration

- Node resources:
  - `4x H100 80GB`
  - roughly `2 TiB` system RAM
  - `800 GB` `/workspace` volume
- Model download:
  - Hugging Face repo `moonshotai/Kimi-K2.6`
  - local path `/workspace/models/kimi-k2.6`
  - disk footprint about `555 GB`
- Runtime stack:
  - source checkout: `kvcache-ai/ktransformers` branch/tag `v0.5.3`
  - `torch 2.9.1`
  - `transformers 4.57.1`
  - `sglang-kt 0.5.3`
  - `kt-kernel 0.5.3`
  - `nvidia-cudnn-cu12 9.16.0.29`
- Launch parameters:
  - `TP_SIZE=4`
  - `KT_CPUINFER=96`
  - `KT_THREADPOOL_COUNT=2`
  - `KT_NUM_GPU_EXPERTS=30`
  - `KT_METHOD=RAWINT4`
  - `KT_GPU_PREFILL_TOKEN_THRESHOLD=400`
  - `MEM_FRACTION_STATIC=0.94`
  - `CHUNKED_PREFILL_SIZE=32658`
  - `MAX_TOTAL_TOKENS=50000`
  - `ATTENTION_BACKEND=flashinfer`
  - `DISABLE_CUDA_GRAPH=1`

## Commands

```bash
# Launch the official-template H100 pod
runpodctl pod create \
  --template-id runpod-torch-v280 \
  --gpu-id "NVIDIA H100 80GB HBM3" \
  --gpu-count 4 \
  --cloud-type SECURE \
  --volume-in-gb 800 \
  --ports 30000/http,22/tcp,31245/http \
  --global-networking

# Download the full model
source /workspace/venv/bin/activate
hf download moonshotai/Kimi-K2.6 --local-dir /workspace/models/kimi-k2.6

# Source-build the compatible KTransformers stack
git clone --branch v0.5.3 --depth 1 --recurse-submodules \
  https://github.com/kvcache-ai/ktransformers.git \
  /workspace/src/ktransformers-v053
apt-get update
apt-get install -y pkg-config ninja-build libhwloc-dev
source /workspace/venv053/bin/activate
cd /workspace/src/ktransformers-v053
bash ./install.sh all --no-clean
pip install nvidia-cudnn-cu12==9.16.0.29

# Launch serving
source /workspace/venv053/bin/activate
export PYTHONPATH=/workspace/src/ktransformers-v053:$PYTHONPATH
DISABLE_CUDA_GRAPH=1 \
MODEL_PATH=/workspace/models/kimi-k2.6 \
KT_WEIGHT_PATH=/workspace/models/kimi-k2.6 \
PORT=31245 \
TP_SIZE=4 \
HOST=0.0.0.0 \
/workspace/gpu-deployment-experiments/scripts/serve/start_ktransformers_kimi_k26_sglang.sh

# Smoke
python /workspace/gpu-deployment-experiments/scripts/benchmark/smoke_openai.py \
  --base-url http://127.0.0.1:31245/v1 \
  --model Kimi-K2.6 \
  --instant \
  --max-tokens 64

# Benchmarks
python /workspace/gpu-deployment-experiments/scripts/benchmark/benchmark_openai.py \
  --base-url http://127.0.0.1:31245/v1 \
  --model Kimi-K2.6 \
  --instant \
  --requests 4 \
  --concurrency 1 \
  --max-tokens 32 \
  --output /workspace/results/kimi-k26-ktransformers-h100x4-c1.jsonl
```

## Results

| Metric | Value |
| --- | --- |
| Server startup time | about `309 s` |
| Cold first completion | successful, but materially slower than warm runs |
| Warm throughput, `c1` | `6.25 output tok/s`, `0.195 req/s`, `5.12 s` avg latency |
| Warm throughput, `c2` | `12.11 output tok/s`, `0.378 req/s`, `5.22 s` avg latency |
| Warm throughput, `c4` | `15.59 output tok/s`, `0.487 req/s`, `8.04 s` avg latency |
| Error rate | `0 / 12` benchmark requests |
| Peak GPU memory observed | about `30.2 GiB` per GPU during warm requests |
| Idle post-load GPU memory | about `21-22 GiB` per GPU |

## Observations

- This was the first RunPod node in the whole effort that became actually reachable and stayed usable.
- Official RunPod templates were materially more reliable than the custom-image launches that kept failing on MI300X and several NVIDIA classes.
- PyPI wheels alone were not enough for this stack. The source install was required because the compatible `kt-kernel 0.5.3` wheel was not published even though `ktransformers 0.5.3` expects it.
- `nvidia-cudnn-cu12 9.16.0.29` was required to avoid the known bad `torch 2.9.1 + cuDNN 9.10` combination that SGLang rejects.
- Disabling CUDA graph capture avoided the earlier startup failures on this setup.
- SGLang warned that it was using default fused-MoE kernel configs for `H100 80GB`, so there is still headroom for tuning.

## Follow-Ups

- Add wider token sweeps and sustained soak runs on this exact profile.
- Try a larger NVIDIA pod for `vLLM` and pure `SGLang` so the framework comparison is apples-to-apples on a full-GPU deployment.
- Revisit AMD only after RunPod MI300X readiness is reliable; the pod-allocation path is still the blocker there.
