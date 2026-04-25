# 2026-04-25 RunPod 2x MI300X Q2 Attempt

## Goal

Test whether `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` can be served on the smallest practical AMD RunPod topology: 2x MI300X.

## Why This Topology

- `UD-Q2_K_XL` is the smallest public Kimi K2.6 GGUF artifact currently exposed by Unsloth.
- The artifact size is documented as `340 GB`.
- 2x MI300X provides `384 GB` aggregate VRAM, which is the smallest RunPod MI300X shape that should plausibly fit the quantized model with a short context window.

Sources:

- https://huggingface.co/unsloth/Kimi-K2.6-GGUF
- https://unsloth.ai/docs/models/kimi-k2.6

## Launch Parameters

| Field | Value |
| --- | --- |
| Date | `2026-04-25` |
| Pod name | `kimi-k26-gguf-q2-mi300x2-20260425-1` |
| Pod ID | `0g06vsh8v3rqxw` |
| Machine ID | `j03rnq2tcsxu` |
| Cloud | `SECURE` |
| Datacenter | `EU-RO-1` |
| GPU | `AMD Instinct MI300X OAM` |
| GPU count | `2` |
| Cost | `$3.98/hr` |
| Image | `rocm/llama.cpp:llama.cpp-b6356_rocm7.0.0_ubuntu24.04_server` |
| Volume | `500 GB` |
| Port | `30000/http` |
| Model | `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` |
| Context length | `2048` |
| KV cache | `q8_0` |
| Tensor split | `1,1` |

The RunPod launcher used `dockerEntrypoint=["bash","-lc"]` and executed `scripts/serve/start_llamacpp_kimi_k26_gguf_rocm.sh` inline.

## Result

The pod never became usable.

Observed state during the startup window:

- `desiredStatus: RUNNING`
- `uptimeSeconds: 0`
- `publicIp: null`
- SSH status: `pod not ready`
- HTTP endpoint: unavailable because the runtime never received routing

The pod sat in that state for more than four minutes. Since `uptimeSeconds` never moved off zero, the failure happened before `llama-server` could start. This is consistent with the earlier MI300X readiness failures on the same RunPod machine family.

## Interpretation

This attempt does not tell us that `2x MI300X` is too small for the Q2 model. It tells us that the current RunPod MI300X host allocated for this test did not transition into a live runtime at all.

So the blocker remains infrastructure readiness, not model memory fit.

## Cleanup

- Pod deleted after the failed startup window.
- `runpodctl pod list` returned `[]` afterward.
- Account spend returned to the unrelated baseline.
