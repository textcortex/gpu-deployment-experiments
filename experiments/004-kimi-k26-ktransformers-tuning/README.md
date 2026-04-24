# Experiment 004: Kimi K2.6 KTransformers Tuning on RunPod 4x H100

Status: completed initial tuning sweep

## Goal

Tune the working `4x H100 80GB` KTransformers deployment to improve output throughput over experiment `003-kimi-k26-ktransformers-h100x4`.

## Focus Areas

- CPU inference threads and thread pool layout
- GPU expert count
- Deferred expert pipelining
- Request scheduler window
- Any launch changes that improve warm output tok/s without breaking startup

## Runs

| Config | Key settings | Requests | Concurrency | Max tokens | Output tok/s | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `exp003-repro-warm2` | `KT_CPUINFER=96`, `KT_THREADPOOL_COUNT=2`, `KT_NUM_GPU_EXPERTS=30` | `4` | `4` | `32` | `0.688` | Reproduces the poor steady-state behavior on this host. |
| `e120-mrr4-warm2` | `KT_CPUINFER=96`, `KT_THREADPOOL_COUNT=2`, `KT_NUM_GPU_EXPERTS=120`, `MAX_RUNNING_REQUESTS=4` | `4` | `4` | `32` | `0.735` | More GPU experts alone help only slightly on this host. |
| `numa4-e120-warm2` | `KT_CPUINFER=64`, `KT_THREADPOOL_COUNT=4`, `KT_NUM_GPU_EXPERTS=120`, `MAX_RUNNING_REQUESTS=4` | `4` | `4` | `32` | `2.110` | Best result so far. About `3.07x` faster than `exp003-repro-warm2`. |

## Current Best

Best warm result on this node:

- `2.110 output tok/s`
- `0.066 req/s`
- `60.217 s` average latency

The winning change was not GPU experts by itself. The decisive step was aligning KTransformers to this host's `4` NUMA nodes:

- `KT_CPUINFER=64`
- `KT_THREADPOOL_COUNT=4`
- `KT_NUM_GPU_EXPERTS=120`
- `MAX_RUNNING_REQUESTS=4`

Raw outputs and logs are stored in [`results/`](./results/).
