# Research: Kimi K2.6 on AMD MI300X

Date: 2026-04-23

## Summary

Kimi K2.6 is a 1T-parameter MoE model with 32B active parameters and a 256K-token context window. Moonshot's model card says Kimi K2.6 uses the same architecture as Kimi K2.5, so K2.5 deployment methods can be reused. The officially named engines are vLLM, SGLang, and KTransformers.

For the first RunPod MI300X experiment, start with SGLang:

- The SGLang Kimi K2.6 cookbook has explicit MI300X guidance.
- It recommends 4x MI300X/MI325X with `--tp 4`.
- It warns that AMD tensor parallelism must be `<= 4` for this model because Kimi K2.6 has 64 attention heads and the AMD AITER MLA kernel requires `heads_per_gpu % 16 == 0`.
- It recommends `--context-length 128000`, `--kv-cache-dtype fp8_e4m3`, and `--mem-fraction-static 0.8` to conserve memory on AMD.

vLLM is also viable. The Kimi K2.6 deployment guide says vLLM 0.19.1 has been manually verified, and the vLLM Kimi K2.5 recipe says AMD support uses 8x MI300X/MI325X/MI355X with ROCm 7.2.1 and Python 3.12. That is a good second experiment once the SGLang baseline is captured.

The Moonshot deployment guide says SGLang v0.5.10 or later is the stable support line. If the AMD ROCm image still ships an older SGLang build, set `PRE_START_CMD='uv pip install "sglang>=0.5.10.post1" --prerelease=allow'` for a one-off upgrade before serving, or replace `IMAGE_NAME` with a newer ROCm image once one is published.

## RunPod Notes

RunPod spot instances are represented as interruptible pods in the REST API. The installed `runpodctl pod create` command currently does not expose an interruptible flag, so this repository uses `POST /v1/pods` with `"interruptible": true` for spot deployments.

RunPod network volumes are the right storage primitive for this experiment because model weights are large and spot pods can disappear. Network volumes persist independently from compute, mount at `/workspace` for pods, and must be created in the same datacenter as the pod.

Local availability snapshot from `runpodctl` on 2026-04-23:

- `AMD Instinct MI300X OAM` is available, Secure Cloud only, low stock.
- `EU-RO-1` advertises MI300X availability.

This availability changes frequently, so always run `scripts/runpod/check_availability.sh` before creating resources.

## Proposed First Configuration

| Field | Value |
| --- | --- |
| Provider | RunPod |
| GPU | AMD Instinct MI300X OAM |
| GPU count | 4 |
| Pod type | Spot / interruptible |
| Cloud | Secure Cloud |
| Datacenter | `EU-RO-1` initially, re-check before launch |
| Persistent storage | Network volume mounted at `/workspace` |
| Serving engine | SGLang |
| Model | `moonshotai/Kimi-K2.6` |
| Tensor parallelism | `--tp 4` |
| Port | `30000/http` |

## Smaller MI300X Fallback

Kimi K2.6 is too large to treat 1x or 2x MI300X as normal serving baselines. The Hugging Face repository is about 595 GB, while each MI300X has 192 GB VRAM.

A 2x MI300X fallback may be worth testing only with CPU offload and a short context window:

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

This is a feasibility probe, not a performance baseline. If it works, benchmark results should be labeled separately from full-GPU 4x MI300X results.

## Serve Command

```bash
sglang serve \
  --model-path moonshotai/Kimi-K2.6 \
  --tp 4 \
  --trust-remote-code \
  --reasoning-parser kimi_k2 \
  --tool-call-parser kimi_k2 \
  --host 0.0.0.0 \
  --port 30000 \
  --context-length 128000 \
  --kv-cache-dtype fp8_e4m3 \
  --mem-fraction-static 0.8
```

## Validation Plan

1. Create or reuse a network volume in the target MI300X datacenter.
2. Create a spot pod with `interruptible: true`, 4x MI300X, the SGLang ROCm image, and port `30000/http`.
3. Confirm ROCm visibility inside the pod with `rocminfo` and `python -c 'import torch; print(torch.cuda.device_count())'`.
4. Start SGLang and watch startup logs until the OpenAI-compatible endpoint is live.
5. Run a smoke prompt against `/v1/chat/completions`.
6. Run throughput tests with fixed prompts and increasing concurrency.
7. Save benchmark JSONL and a Markdown run log under `results/` and `experiments/001-mi300x-kimi-k26/`.
8. Terminate the spot pod immediately after capture. Keep the network volume only if model cache reuse is worth the storage cost.

## Sources

- Moonshot Hugging Face model card: https://huggingface.co/moonshotai/Kimi-K2.6
- Moonshot deployment guide: https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/docs/deploy_guidance.md
- SGLang Kimi K2.6 cookbook: https://cookbook.sglang.io/autoregressive/Moonshotai/Kimi-K2.6
- vLLM Kimi K2.5 recipe: https://recipes.vllm.ai/moonshotai/Kimi-K2.5
- RunPod pod pricing and spot behavior: https://docs.runpod.io/pods/pricing
- RunPod pod REST API: https://docs.runpod.io/api-reference/pods/POST/pods
- RunPod network volumes: https://docs.runpod.io/storage/network-volumes
