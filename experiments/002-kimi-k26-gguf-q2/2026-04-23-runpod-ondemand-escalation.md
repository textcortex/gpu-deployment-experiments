# RunPod On-Demand Escalation: 2026-04-23

## Metadata

| Field | Value |
| --- | --- |
| Date | 2026-04-23 |
| Provider | RunPod |
| Model target | `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL` |
| Objective | Get any sufficiently large on-demand node online, then benchmark |
| Result | Allocation succeeded on some larger nodes, but pods never became actually reachable |

## Goal

Stop optimizing only for spot price and escalate through increasingly expensive on-demand GPU options until a usable RunPod pod is available.

## What Changed

Added on-demand launchers:

- `scripts/runpod/create_kimi_k26_gguf_pod_rest.sh`
- `scripts/runpod/create_on_demand_pod_graphql.sh`

These use checked-in startup scripts and allow idle readiness probes with `CUSTOM_START_CMD='sleep infinity'`.

## Price Ladder Used

For the 350 GB+ RAM/VRAM GGUF target, the practical on-demand ladder used on 2026-04-23 was:

| Order | GPU setup | Cloud | Approx cost/hr | Outcome |
| --- | --- | --- | ---: | --- |
| 1 | 8x RTX A6000 | Community | `$2.64` | No capacity |
| 2 | 8x A40 | Secure | `$3.52` | No capacity |
| 3 | 8x RTX A6000 | Secure | `$3.92` | No capacity |
| 4 | 8x L40 | Community | `$5.52` | No capacity |
| 5 | 8x RTX 6000 Ada | Community | `$5.92` | No capacity |
| 6 | 5x A100 PCIe | Community | `$5.95` | No capacity |
| 7 | 4x RTX PRO 6000 | Community | `$6.76` | Allocated, but never became reachable |
| 8 | 5x H100 SXM | Community | `$13.45` | No capacity across tested datacenters |
| 9 | 2x B200 | Secure | `$10.98` | No capacity |
| 10 | 3x H200 NVL | Secure | `$10.17` | No capacity |
| 11 | 3x H200 SXM | Secure | `$11.97` | Allocated, but never became reachable |

## Allocated But Unusable Pods

### 4x RTX PRO 6000 Community

Pod `9gb186sklrytw3`:

- Allocated in Community Cloud on 2026-04-23
- Cost: `$6.76/hr`
- Startup command attempted to build and launch llama.cpp
- Pod remained at `uptimeSeconds: 0`, with no SSH or HTTP routing

Idle repro pod `w7j86y1ke9m53s` on the same GPU class:

- Same GPU class, `sleep infinity`
- SSH metadata eventually appeared
- Actual SSH port still refused connections
- Pod deleted after readiness failed

### 3x H200 SXM Secure

Pod `hlh0juq7ggs32e` in `EU-FR-1`:

- Allocated at `$11.97/hr`
- Idle command: `sleep infinity`
- SSH metadata eventually appeared with IP and port
- Actual SSH port still refused connections for repeated retries
- Pod deleted after readiness failed

## Interpretation

The dominant blocker on RunPod today was not Kimi K2.6 itself and not the benchmark client. The blocker was pod readiness after allocation:

- RunPod sometimes returned `desiredStatus: RUNNING`
- SSH metadata could appear later
- But the actual TCP endpoint still refused connections
- This happened even with an idle startup command, so it was not caused only by the model build or download path

## Cleanup

All on-demand pods created during the escalation were deleted. After cleanup:

- `runpodctl pod list` returned `[]`
- `runpodctl user` returned `currentSpendPerHr: 0.139`

That remaining spend was from a pre-existing serverless endpoint, not these experiments.

## Immediate Next Step

Do not spend more time trying to benchmark frameworks on a pod that is not reachable. The next attempt should begin with a known-good idle readiness probe on a different provider or a RunPod path that bypasses this pod-readiness failure mode.
