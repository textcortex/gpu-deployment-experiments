# Experiment 002: Kimi K2.6 GGUF Q2 on Cheapest Viable RunPod GPUs

Status: blocked by RunPod capacity and pod readiness reliability

## Goal

Run the smallest practical Kimi K2.6 deployment we can test on RunPod, then measure smoke latency and throughput with the existing OpenAI-compatible benchmark scripts.

## Model Choice

Use `unsloth/Kimi-K2.6-GGUF` with the `UD-Q2_K_XL` split GGUF. This is the smallest currently published Kimi K2.6 GGUF quant in the repository, with Unsloth documenting a 340 GB disk footprint and a 350 GB+ RAM/VRAM target. It is the lower-VRAM path compared with the full `moonshotai/Kimi-K2.6` checkpoint and can be served by llama.cpp.

Sources:

- https://huggingface.co/unsloth/Kimi-K2.6-GGUF
- https://unsloth.ai/docs/models/kimi-k2.6
- https://huggingface.co/docs/hub/gguf-llamacpp

## Cheapest Node Selection

For a 350 GB+ RAM/VRAM target, the cheapest RunPod candidates observed on 2026-04-23 were:

| Rank | Cloud | GPU | Count | Aggregate VRAM | Observed GPU price | Result |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 1 | Community | RTX A6000 48GB | 8 | 384 GB | `$2.00/hr` | No 8-GPU spot capacity in tested datacenters |
| 2 | Secure | A40 48GB | 8 | 384 GB | `$2.96/hr` | Allocated in `EU-SE-1`, but pod never reached usable startup before outbid |
| 3 | Secure | RTX A6000 48GB | 8 | 384 GB | `$3.36/hr` | Not tried after A40 startup failed |
| 4 | Secure | MI300X 192GB | 2 | 384 GB | `$3.38/hr` | Not tried in this GGUF pass; MI300X spot capacity failed in experiment 001 |
| 5 | Community | A100 SXM 80GB | 5 | 400 GB | `$3.95/hr` | No 5-GPU spot capacity in tested datacenters |
| 6 | Community | H100 NVL | 4 | >= 376 GB | `$5.60/hr` | No 4-GPU spot capacity in tested datacenters |

The selected target was 8x RTX A6000 Community first because it was the cheapest aggregate-VRAM fit. The fallback target was 8x A40 Secure because it was the cheapest configuration that actually allocated a machine.

## 2026-04-25 2x MI300X ROCm Attempt

A direct AMD GGUF attempt was made on 2026-04-25 because 2x MI300X is the smallest native RunPod MI300X topology that should fit the `UD-Q2_K_XL` artifact in aggregate VRAM.

Configuration:

| Field | Value |
| --- | --- |
| Cloud | Secure |
| Datacenter | `EU-RO-1` |
| GPU | `AMD Instinct MI300X OAM` |
| GPU count | `2` |
| Aggregate VRAM | `384 GB` |
| Image | `rocm/llama.cpp:llama.cpp-b6356_rocm7.0.0_ubuntu24.04_server` |
| Model | `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` |
| Context | `2048` |
| Tensor split | `1,1` |
| Port | `30000/http` |

Outcome:

- Pod `0g06vsh8v3rqxw` allocated at `$3.98/hr`.
- RunPod placed it on machine `j03rnq2tcsxu`, the same MI300X host family that had already failed earlier full-checkpoint attempts.
- For more than four minutes after allocation, `desiredStatus` remained `RUNNING` but `uptimeSeconds` stayed `0`.
- No public IP was assigned, HTTP never came up, and SSH remained `pod not ready`.
- The pod was deleted without benchmark data because the runtime never became reachable.

This failure mode points to RunPod host readiness, not model fit. The deployment never reached the point where `llama-server` could start downloading or loading the GGUF.

## 2026-04-25 4x RTX PRO 6000 Attempts

Three `4x RTX PRO 6000 Blackwell Server Edition` attempts were made on 2026-04-25 for the same `UD-Q2_K_XL` GGUF using llama.cpp CUDA with explicit multi-GPU sharding enabled.

Configuration:

| Field | Value |
| --- | --- |
| Cloud | Community |
| GPU | `NVIDIA RTX PRO 6000 Blackwell Server Edition` |
| GPU count | `4` |
| Aggregate VRAM | `384 GB` |
| Image | `runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404` |
| Model | `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` |
| Context | `2048` |
| Split mode | `layer` |
| Tensor split | `1,1,1,1` |
| Port | `30000/http` |

Outcome:

- First pod: `eleak5xoojla2a`
- Second pod: `qm93vevzo0cz1j`
- Third pod: `2qlu7nwua4ndd8`
- All three landed on the same machine family: `9ti6j8484pn1`
- First attempt never exposed reachable SSH
- Second attempt later exposed SSH metadata (`107.150.186.62:13340`) but direct SSH still returned `Connection refused`
- Third attempt later exposed SSH metadata (`107.150.186.62:13262`) but direct SSH still returned `Connection refused`
- In all three cases `uptimeSeconds` remained `0`, so the runtime never transitioned into a usable state

These attempts confirm that the current RunPod `4x RTX PRO 6000` allocator is also returning a non-ready host for this workflow.

## 2026-04-25 Cheapest-Available Search

An explicit cheapest-first search was run on 2026-04-25 against the live RunPod inventory for the `UD-Q2_K_XL` GGUF path. The target requirement was the smallest practical even-GPU topology with enough aggregate VRAM to plausibly serve the 340 GB artifact.

Observed order from the live market:

| Candidate | Result |
| --- | --- |
| `8x A40` | cheapest likely fit, but no allocatable instances |
| `8x RTX A6000` | no allocatable instances |
| `2x MI300X` | allocated at `$3.98/hr`, but host never transitioned into a live runtime |
| `4x H100 80GB` | no allocatable instances in REST-allowed H100 regions |
| `4x H100 NVL` | allocated at `$10.36/hr`, but host never transitioned into a live runtime |
| `4x H200` | no allocatable instances |
| `4x RTX PRO 6000 Secure` | allocated at `$7.56/hr`, new host, but still never transitioned into a live runtime |

Conclusion:

- The cheapest allocatable shape today was `2x MI300X` at `$3.98/hr`.
- The cheapest allocatable NVIDIA shape today was `4x RTX PRO 6000 Secure` at `$7.56/hr`.
- None of the allocatable shapes actually became reachable enough to run inference, so there is still no successful cheap RunPod baseline for this model on this date.

## Launch Runbook

Capacity probe with a disposable pod volume:

```bash
ALLOW_POD_VOLUME=1 \
VOLUME_GB=500 \
CLOUD_TYPE=SECURE \
GPU_TYPE_ID='NVIDIA A40' \
GPU_COUNT=8 \
BID_PER_GPU=0.37 \
DATA_CENTER_ID=EU-SE-1 \
IMAGE_NAME=runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404 \
MIN_MEMORY_GB=128 \
scripts/runpod/create_kimi_k26_gguf_spot_pod.sh
```

The wrapper embeds `scripts/serve/start_llamacpp_kimi_k26_gguf_cuda.sh` into `CUSTOM_START_CMD` so the pod does not need this repository pre-cloned.

On-demand escalation scripts:

```bash
# REST path with datacenter list support limited by RunPod's published allowlist.
scripts/runpod/create_kimi_k26_gguf_pod_rest.sh

# GraphQL path for newer datacenters and direct on-demand pod creation.
scripts/runpod/create_on_demand_pod_graphql.sh
```

## Smoke Test

```bash
python scripts/benchmark/smoke_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "unsloth/Kimi-K2.6-GGUF"
```

## Benchmark

```bash
python scripts/benchmark/benchmark_openai.py \
  --base-url "http://POD_HOST:30000/v1" \
  --model "unsloth/Kimi-K2.6-GGUF" \
  --requests 16 \
  --concurrency 1 \
  --max-tokens 256 \
  --output results/002-kimi-k26-gguf-q2-c1.jsonl
```

Increase concurrency only after the first successful run:

| Sweep | Values |
| --- | --- |
| Concurrency | 1, 2, 4 |
| Context length | 4096, 8192 |
| Max tokens | 128, 256, 512 |
| Backend | llama.cpp CUDA |
| Quant | `UD-Q2_K_XL` |

## Stop Condition

Delete every disposable pod after each attempt:

```bash
scripts/runpod/delete_pod.sh POD_ID
```

Disposable pod volumes are deleted with the pod. Network volumes remain billable and must be deleted separately.
