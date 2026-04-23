# Kimi K2.6 GGUF Low-VRAM Route

Date: 2026-04-23

## Sources

- Unsloth Kimi K2.6 local guide: https://unsloth.ai/docs/models/kimi-k2.6
- Unsloth Kimi K2.6 GGUF files: https://huggingface.co/unsloth/Kimi-K2.6-GGUF
- Hugging Face GGUF with llama.cpp guide: https://huggingface.co/docs/hub/gguf-llamacpp
- RunPod pod API docs: https://docs.runpod.io/api-reference/pods/POST/pods
- RunPod storage troubleshooting note: https://docs.runpod.io/pods/troubleshooting/zero-gpus

## Findings

Unsloth documents `UD-Q2_K_XL` as the practical low-memory Kimi K2.6 route: 340 GB on disk and a 350 GB+ RAM/VRAM target. The public Hugging Face repository currently exposes `UD-Q2_K_XL`, `UD-Q4_K_XL`, and `UD-Q8_K_XL`; no smaller Kimi K2.6 GGUF quant was present in the public file list at the time of the check.

Hugging Face documents llama.cpp support for pulling GGUF models directly from a Hugging Face repo with `-hf`, and the server exposes an OpenAI-compatible chat completions endpoint. That makes the same benchmark scripts usable for SGLang and llama.cpp as soon as the endpoint is reachable.

RunPod supports interruptible pods for lower cost, but they can be stopped or outbid. Network volumes are preferred when model weights have been downloaded because they decouple cached model data from a specific pod machine. For initial capacity probes, disposable pod volumes avoid leaving billable network storage behind.

## Decision

Use `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` with llama.cpp for the cheapest low-VRAM experiment. Rank GPU nodes by aggregate VRAM >= 350 GB, then sort by observed spot price.

The cheapest observed fit on 2026-04-23 was 8x RTX A6000 Community Cloud. Since that did not allocate, the next fallback was 8x A40 Secure Cloud.

## Repro Path

```bash
ALLOW_POD_VOLUME=1 \
VOLUME_GB=500 \
CLOUD_TYPE=SECURE \
GPU_TYPE_ID='NVIDIA A40' \
GPU_COUNT=8 \
BID_PER_GPU=0.37 \
DATA_CENTER_ID=EU-SE-1 \
scripts/runpod/create_kimi_k26_gguf_spot_pod.sh
```

Then benchmark:

```bash
python scripts/benchmark/smoke_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "unsloth/Kimi-K2.6-GGUF"

python scripts/benchmark/benchmark_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "unsloth/Kimi-K2.6-GGUF" \
  --requests 16 \
  --concurrency 1 \
  --max-tokens 256 \
  --output results/002-kimi-k26-gguf-q2-c1.jsonl
```
