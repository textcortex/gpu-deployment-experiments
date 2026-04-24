# RunPod Kimi K2.6 Tuning: 2026-04-24

## Metadata

| Field | Value |
| --- | --- |
| Experiment | `004-kimi-k26-ktransformers-tuning` |
| Date | 2026-04-24 |
| Provider | RunPod |
| GPU type | `NVIDIA H100 80GB HBM3` |
| GPU count | `4` |
| Serving engine | `KTransformers via sglang.launch_server` |
| Model | `moonshotai/Kimi-K2.6` |

## Purpose

Find a faster warm-throughput configuration than experiment `003-kimi-k26-ktransformers-h100x4` on a working RunPod `4x H100` node.

## Baseline To Beat

- `15.59 output tok/s`
- `0.487 req/s`
- `8.04 s` average latency
- conditions: `4` requests, concurrency `4`, `32` max tokens, `KT_NUM_GPU_EXPERTS=30`

## Notes

### Environment

- Provider: RunPod
- Datacenter: `AP-IN-1`
- Pod ID: `1q5aarpjpefgyp`
- GPU: `4x NVIDIA H100 80GB HBM3`
- CPU: `Intel Xeon Platinum 8462Y+`
- Host topology observed during install: `64` cores / `4` NUMA nodes
- Model path: `/workspace/models/kimi-k2.6`
- Stack: source-built `ktransformers v0.5.3` + `sglang-kt v0.5.3`

### What Broke

- On this host, `GET /v1/models` is a false-ready signal for Kimi K2.6 with KTransformers.
- The endpoint comes up before late MoE and workspace setup is really done.
- The original harness therefore started smoke too early and looked hung.
- Fix applied locally: `scripts/benchmark/run_ktransformers_trial.sh` now waits `POST_READY_SLEEP_SECS` after `/v1/models` becomes available.

### Comparable Runs

All numbers below are from the second warm benchmark pass against the same live server, using:

- prompt file: `scripts/benchmark/prompts/kimi_throughput_short.txt`
- `4` requests
- concurrency `4`
- `32` max tokens
- `128` total output tokens per sweep

| Config | Settings | Wall s | Avg latency s | Output tok/s | Req/s |
| --- | --- | ---: | ---: | ---: | ---: |
| `exp003-repro-warm2` | `KT_CPUINFER=96`, `KT_THREADPOOL_COUNT=2`, `KT_NUM_GPU_EXPERTS=30` | `186.179` | `184.784` | `0.688` | `0.021` |
| `e120-mrr4-warm2` | `KT_CPUINFER=96`, `KT_THREADPOOL_COUNT=2`, `KT_NUM_GPU_EXPERTS=120`, `MAX_RUNNING_REQUESTS=4` | `174.136` | `172.891` | `0.735` | `0.023` |
| `numa4-e120-warm2` | `KT_CPUINFER=64`, `KT_THREADPOOL_COUNT=4`, `KT_NUM_GPU_EXPERTS=120`, `MAX_RUNNING_REQUESTS=4` | `60.665` | `60.217` | `2.110` | `0.066` |

### Result

The best warm throughput on this host was:

- `2.110 output tok/s`
- `0.066 req/s`
- `60.217 s` average latency

Relative to the reproduced `30`-expert / `2`-pool baseline on the same host:

- output tok/s improved by about `3.07x`
- request throughput improved by about `3.10x`
- average latency dropped by about `67%`

### Interpretation

- Raising `KT_NUM_GPU_EXPERTS` from `30` to `120` alone was not enough. It improved warm output throughput only from `0.688` to `0.735`.
- The real gain came from matching the KTransformers worker layout to this host's `4` NUMA nodes.
- On this machine, the `2`-pool shape copied from the earlier successful H100 host left too much work on an unfavorable CPU path.
- The tuned `4`-pool variant is still much slower than the earlier H100 host from experiment `003`, but it is the best result obtained on this node.

### Artifacts

- `results/kimi-k26-h100x4-exp003-repro.jsonl`
- `results/kimi-k26-h100x4-exp003-repro-warm2.jsonl`
- `results/kimi-k26-h100x4-e120-mrr4.jsonl`
- `results/kimi-k26-h100x4-e120-mrr4-warm2.jsonl`
- `results/kimi-k26-h100x4-numa4-e120.jsonl`
- `results/kimi-k26-h100x4-numa4-e120-warm2.jsonl`
- server logs for each run are stored alongside the JSONL files in `results/`
