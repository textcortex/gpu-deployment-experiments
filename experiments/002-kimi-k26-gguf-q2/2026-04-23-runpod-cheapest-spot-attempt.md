# RunPod Cheapest GGUF Attempt: 2026-04-23

## Metadata

| Field | Value |
| --- | --- |
| Date | 2026-04-23 |
| Provider | RunPod |
| Target model | `unsloth/Kimi-K2.6-GGUF` |
| Quantization | `UD-Q2_K_XL` |
| Serving engine | llama.cpp |
| Pod type | Spot / interruptible |
| Storage | Disposable pod volume for capacity probes |
| Result | No benchmark; cheapest capacity failed or never became usable |

## Goal

Pick the cheapest RunPod GPU node that satisfies the smallest practical Kimi K2.6 VRAM requirement, launch it as spot, expose a llama.cpp OpenAI-compatible endpoint, then measure speed with the repo benchmark scripts.

## Cheapest Configuration Search

The lower-VRAM model path was `unsloth/Kimi-K2.6-GGUF` `UD-Q2_K_XL`, the smallest currently published Kimi K2.6 GGUF quant in the repository. Unsloth documents it at 340 GB on disk and recommends 350 GB+ RAM/VRAM, so the RunPod target was at least 350 GB aggregate VRAM. The cheapest observed candidate was 8x RTX A6000 Community Cloud at about `$2.00/hr`, giving 384 GB aggregate VRAM.

Launch attempts:

| Target | Datacenters | Result |
| --- | --- | --- |
| 8x RTX A6000 Community | `EU-RO-1` with network volume | No spot capacity |
| 8x RTX A6000 Community | `CA-MTL-3`, `EU-SE-1`, `US-KS-2`, `US-TX-1` with disposable pod volume | No spot capacity |
| 8x A40 Secure | `CA-MTL-1` | No spot capacity |
| 8x A40 Secure | `EU-SE-1` | Allocated, but pod did not become usable |

## A40 Startup Attempts

The A40 fallback used 8x A40 Secure Cloud in `EU-SE-1` with `BID_PER_GPU=0.37` and a 500 GB disposable pod volume.

Tried startup paths:

1. `ghcr.io/ggml-org/llama.cpp:server-cuda` with llama.cpp server arguments passed through RunPod docker args.
2. RunPod PyTorch CUDA base image that installs build tools, builds llama.cpp with `GGML_CUDA=ON`, then starts `llama-server`.
3. Longer retry of the PyTorch CUDA base image to allow image pull and build time.

Observed result:

- The allocated pods never opened SSH or the HTTP server port.
- One retry was marked outbid before reaching usable uptime.
- Because no OpenAI-compatible endpoint came up, `smoke_openai.py` and `benchmark_openai.py` could not run.

## Benchmark Result

| Metric | Value |
| --- | --- |
| Startup time | Not measured; pod never reached usable startup |
| Time to first token | Not measured |
| Output tokens/sec | Not measured |
| Requests/sec | Not measured |
| Error rate | 100% for endpoint availability |
| Peak GPU memory | Not measured |
| Notes | Blocked before model download/load |

## Repro Commands

The next identical retry should use the checked-in wrapper rather than a pasted one-off command:

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

## Cleanup

All pods created for this experiment were deleted or had already exited after being outbid. `runpodctl pod list` and `runpodctl network-volume list` returned empty arrays after cleanup.

The account still showed `$0.139/hr` spend from an unrelated existing serverless endpoint, not from this experiment.

After the attempt, the GraphQL launcher was updated to support disposable pod volumes and to shell-quote multi-line custom startup commands as a single command string. The next retry should use `scripts/runpod/create_kimi_k26_gguf_spot_pod.sh`.

## Second Live Spot Pass

After fixing the launcher and adding the reusable wrapper, another live spot pass was run:

| Target | Datacenters | Result |
| --- | --- | --- |
| 8x RTX A6000 Community | `CA-MTL-3`, `EU-SE-1`, `US-KS-2`, `US-TX-1`, `EU-RO-1` | No spot capacity |
| 8x A40 Secure | `CA-MTL-1`, `EU-SE-1` | No spot capacity |
| 5x A100 SXM Community | `EU-RO-1`, `EUR-IS-1`, `US-CA-2`, `US-KS-2`, `US-MD-1`, `US-MO-1`, `US-WA-1` | No spot capacity |
| 4x H100 NVL Community | `EUR-IS-1`, `OC-AU-1`, `US-CA-2`, `US-GA-2`, `US-KS-2` | No spot capacity |

No pods were allocated in the second pass, so no benchmark endpoint was created.

## Conclusion

The cheapest small-VRAM route is not currently blocked by the benchmark client or model-serving plan. It is blocked earlier by RunPod spot capacity and startup reliability:

- 8x RTX A6000 Community is the cheapest aggregate-VRAM match but had no spot capacity in tested datacenters.
- 8x A40 Secure was the cheapest target that allocated in the first pass, but it did not reach SSH/HTTP readiness before being outbid.
- A second pass with the fixed launcher failed at spot allocation across RTX A6000, A40, A100 SXM, and H100 NVL targets.

## Next Retry

Use 8x A40 Secure again with a higher spot bid or an on-demand test window, because it was the only low-cost 384 GB configuration that allocated. If a smaller Kimi K2.6 GGUF quant is published later, lower the aggregate VRAM target and rank the GPU nodes again.
