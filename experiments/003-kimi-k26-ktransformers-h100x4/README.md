# Experiment 003: Kimi K2.6 on RunPod 4x H100 with KTransformers

Status: working baseline on RunPod using official template plus source-built KTransformers stack

## Goal

Get the first actually reachable RunPod node serving the full `moonshotai/Kimi-K2.6` checkpoint, then capture a small but real throughput baseline on hardware we can reproduce.

## What Worked

- Provider: RunPod
- Cloud: Secure
- Datacenter: `AP-IN-1`
- GPU: `4x NVIDIA H100 80GB HBM3`
- Container image: `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`
- Volume: `800 GB`
- Model: `moonshotai/Kimi-K2.6`
- Serving stack: source-built `kt-kernel 0.5.3` + `sglang-kt 0.5.3`

The decisive change was switching from custom images to the official RunPod PyTorch template. That was the first path that produced a pod with working SSH.

## Why KTransformers First

On this hardware, `KTransformers` was the realistic full-checkpoint path:

- `4x H100 80GB` gives `320 GB` aggregate VRAM
- the full Kimi K2.6 checkpoint on `vLLM` or pure `SGLang` still wants materially larger all-GPU footprints
- `KTransformers` can lean on host RAM; this node had roughly `2 TiB` system memory

## Benchmarks

All benchmarks below were warm runs against the OpenAI-compatible endpoint at `http://127.0.0.1:31245/v1`, with:

- `--instant`
- `--max-tokens 32`
- `4` requests

| Sweep | Requests | Concurrency | Avg latency | P95 latency | Requests/s | Output tok/s | Errors |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `c1` | 4 | 1 | `5.12 s` | `5.47 s` | `0.195` | `6.25` | `0` |
| `c2` | 4 | 2 | `5.22 s` | `5.23 s` | `0.378` | `12.11` | `0` |
| `c4` | 4 | 4 | `8.04 s` | `8.07 s` | `0.487` | `15.59` | `0` |

Raw benchmark outputs are stored in this experiment folder:

- `kimi-k26-ktransformers-h100x4-c1.jsonl`
- `kimi-k26-ktransformers-h100x4-c2.jsonl`
- `kimi-k26-ktransformers-h100x4-c4.jsonl`

## Smoke Result

The first successful chat completion answered the test prompt correctly:

- prompt: `Which number is bigger, 9.11 or 9.9?`
- answer: `9.9`
- usage: `27` prompt tokens, `4` completion tokens, `31` total tokens

## Operational Notes

- Startup to ready state was about `5m 09s` from server launch to `Uvicorn running`.
- The first real decode after startup was much slower than the later warm runs.
- GPU memory sat near `21-22 GiB` per GPU while idle after load, and rose to roughly `29-30 GiB` per GPU during warm requests.
- The model directory consumed about `555 GB` on disk, so `500 GB` volume was not enough. `800 GB` was workable.

## Follow-Ups

- Run larger prompt and token sweeps (`128`, `256`, `512`) on this same KTransformers profile.
- Try `vLLM` and pure `SGLang` only on a larger all-GPU node; `4x H100` is better treated as the heterogeneous baseline.
- Tune `KT_NUM_GPU_EXPERTS`, chunk size, and concurrency to find the best cost/performance knee.
