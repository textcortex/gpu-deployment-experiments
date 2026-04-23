# RunPod Spot Attempt: 2026-04-23

## Metadata

| Field | Value |
| --- | --- |
| Date | 2026-04-23 |
| Provider | RunPod |
| Datacenter | `EU-RO-1` |
| Target GPU | `AMD Instinct MI300X OAM` |
| Target model | `moonshotai/Kimi-K2.6` |
| Serving engine | SGLang |
| Pod type | Spot / interruptible |
| Result | Blocked by RunPod MI300X spot capacity |

## Availability Snapshot

`runpodctl gpu list` reported MI300X available in Secure Cloud only with low stock.

`runpodctl datacenter list` reported MI300X availability only in `EU-RO-1`.

No pods were running before or after the attempt.

## Storage

Created a 1000 GB network volume twice for launch attempts:

- `y0dghvynwy`
- `84bwwle85x`

Both were deleted after capacity failures because no pod started and no model data was cached.

## Launch Attempts

### 4x MI300X Baseline

REST API spot pod request:

- `gpuCount`: 4
- `networkVolumeId`: `y0dghvynwy`
- `interruptible`: `true`
- `imageName`: `lmsysorg/sglang:v0.5.9-rocm700-mi30x`
- startup: install `sglang>=0.5.10.post1`, then serve Kimi K2.6 with `--tp 4`

Result:

```json
{
  "error": "create pod: There are no longer any instances available with the request specifications. Please try again later.",
  "status": 500
}
```

GraphQL `podRentInterruptable` with `bidPerGpu=1.99` was retried five times and returned:

```json
{
  "message": "There are no instances available with the request specifications. Please try again later."
}
```

### 2x MI300X CPU-Offload Fallback

Attempted a smaller fallback:

- `gpuCount`: 2
- `tp`: 2
- `context-length`: 8192
- `cpu-offload-gb`: 128
- `minMemoryInGb`: 512
- `bidPerGpu`: 1.99
- `networkVolumeId`: `84bwwle85x`

Result:

```json
{
  "message": "There are no instances available with the request specifications. Please try again later."
}
```

### 1x MI300X CPU-Offload Probe

Attempted an aggressive smaller fallback:

- `gpuCount`: 1
- `tp`: 1
- `context-length`: 4096
- `cpu-offload-gb`: 512
- `minMemoryInGb`: 768
- `bidPerGpu`: 1.99

Result:

```json
{
  "message": "There are no longer any instances available with the request specifications. Please try again later."
}
```

### 1x MI300X Idle Capacity Probe

Attempted an idle 1x MI300X spot pod to separate MI300X capacity from model memory requirements:

- `gpuCount`: 1
- `START_SERVER`: 0
- `minMemoryInGb`: 64
- `minVcpuCount`: 8
- `bidPerGpu`: 1.99

Result:

```json
{
  "message": "There are no instances available with the request specifications. Please try again later."
}
```

### 3x MI300X Pipeline-Parallel Probe

Added pipeline-parallel support to the launcher and attempted a 3x MI300X Kimi K2.6 probe without using invalid tensor parallelism of 3:

- `gpuCount`: 3
- `tp`: 1
- `pipeline-parallel-size`: 3
- `context-length`: 4096
- `cpu-offload-gb`: 64
- `minMemoryInGb`: 512
- `bidPerGpu`: 1.99
- `networkVolumeId`: `5446m9p48n`

GraphQL spot result:

```json
{
  "message": "There are no instances available with the request specifications. Please try again later."
}
```

Then attempted an idle 3x MI300X spot pod with minimal RAM/CPU requirements and the same network volume:

- `gpuCount`: 3
- `START_SERVER`: 0
- `minMemoryInGb`: 64
- `minVcpuCount`: 8
- `bidPerGpu`: 1.99

GraphQL spot result:

```json
{
  "message": "There are no instances available with the request specifications. Please try again later."
}
```

REST spot result with the same network volume:

```json
{
  "error": "create pod: There are no longer any instances available with the request specifications. Please try again later.",
  "status": 500
}
```

Finally attempted a disposable idle 3x MI300X REST spot pod without a network volume to rule out network-volume constraints:

```json
{
  "error": "create pod: There are no longer any instances available with the request specifications. Please try again later.",
  "status": 500
}
```

The temporary network volume `5446m9p48n` was deleted after these failures.

## Conclusion

The immediate blocker is RunPod MI300X spot capacity in `EU-RO-1`, not only the Kimi K2.6 4x configuration. Idle 1x and 3x MI300X spot pods could not be allocated.

The smaller 2x MI300X Kimi K2.6 path remains experimental. It requires CPU offload and a shorter initial context window, and it may fail at model load or perform poorly even if spot capacity becomes available.

The 3x MI300X path is also experimental. It should use pipeline parallelism (`TP=1`, `PP=3`) rather than tensor parallelism (`TP=3`) because Kimi K2.6 has 64 attention heads.

## Next Steps

1. Retry MI300X spot later with `scripts/runpod/create_spot_pod_graphql.sh`.
2. Prefer the 4x MI300X SGLang baseline when capacity is available.
3. Use the 2x MI300X CPU-offload fallback only as an experiment, not as a baseline.
4. Ask before switching to on-demand MI300X, because the current secure on-demand price is higher than spot.
