# 2026-04-25 RunPod 4x RTX PRO 6000 Q2 Attempts

## Goal

Try the `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` path on a non-AMD node that still meets the smallest practical aggregate VRAM target.

## Why This Topology

- Each `RTX PRO 6000 Blackwell Server Edition` has `96 GB` VRAM.
- `4x` gives `384 GB` aggregate VRAM, which is above the `340 GB` GGUF artifact size and keeps the topology in the requested even-GPU pattern.
- llama.cpp supports multi-GPU model sharding through `--split-mode` and `--tensor-split`, so GGUF is a valid multi-GPU path.

Sources:

- https://github.com/ggml-org/llama.cpp
- https://github.com/ggml-org/llama.cpp/discussions/6046
- https://github.com/ggml-org/llama.cpp/discussions/11784

## Launch Configuration

| Field | Value |
| --- | --- |
| Cloud | `COMMUNITY` |
| Image | `runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404` |
| Model | `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` |
| Context length | `2048` |
| GPU layers | `999` |
| Split mode | `layer` |
| Tensor split | `1,1,1,1` |
| Volume | `500 GB` |
| Port | `30000/http` |

The launcher embedded `scripts/serve/start_llamacpp_kimi_k26_gguf_cuda.sh` directly into the pod startup command.

## Attempt 1

| Field | Value |
| --- | --- |
| Pod name | `kimi-k26-gguf-q2-rtxpro6000x4-20260425-1` |
| Pod ID | `eleak5xoojla2a` |
| Cost | `$6.76/hr` |
| Machine ID | `9ti6j8484pn1` |

Observed behavior:

- Pod allocated
- `desiredStatus: RUNNING`
- `uptimeSeconds: 0`
- `publicIp: null`
- SSH remained `pod not ready`

## Attempt 2

| Field | Value |
| --- | --- |
| Pod name | `kimi-k26-gguf-q2-rtxpro6000x4-20260425-2` |
| Pod ID | `qm93vevzo0cz1j` |
| Cost | `$6.76/hr` |
| Machine ID | `9ti6j8484pn1` |

Observed behavior:

- Pod allocated again onto the same machine ID as attempt 1
- RunPod later exposed SSH metadata: `107.150.186.62:13340`
- Direct SSH attempts still returned `Connection refused`
- `uptimeSeconds` remained `0`
- No benchmark was possible because the runtime never became reachable

## Interpretation

This is another provider readiness failure. The second attempt is especially useful because it shows that even after RunPod exposed SSH metadata, the host still was not accepting TCP connections.

That means:

- the issue is not the GGUF format
- the issue is not the multi-GPU split configuration
- the issue is not SSH key auth
- the issue is the allocated RunPod host failing to transition into a live runtime

## Cleanup

Both pods were deleted after the failed readiness windows.
