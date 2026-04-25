# 2026-04-25 RunPod Cheapest Search for Kimi K2.6 GGUF Q2

## Goal

Find the cheapest currently available RunPod topology that can plausibly run `unsloth/Kimi-K2.6-GGUF:UD-Q2_K_XL`, then start it and benchmark if the runtime becomes reachable.

## Selection Rule

Use even-GPU shapes only, and prefer the lowest-cost topology that clears the rough aggregate-VRAM floor for the `340 GB` GGUF artifact.

## Live Cheap-First Search

### 1. 8x A40

- Status in inventory: available, low stock
- Result: `HTTP 500 There are no instances currently available`
- Outcome: could not allocate

### 2. 8x RTX A6000

- Status in inventory: advertised in several regions, but without a strong stock signal
- Result: `HTTP 500 There are no instances currently available`
- Outcome: could not allocate

### 3. 2x MI300X

| Field | Value |
| --- | --- |
| Pod ID | `k9p5qwst0txevv` |
| Cost | `$3.98/hr` |
| Machine ID | `j03rnq2tcsxu` |
| Result | allocated |

Observed behavior:

- `desiredStatus: RUNNING`
- `uptimeSeconds: 0`
- no public routing
- SSH never reached `ready`

Outcome: cheapest allocatable option, but dead host.

### 4. 4x H100 80GB

- Status in inventory: high-level stock existed, but not in the REST-allowed regions that were tested
- Result: `HTTP 500 There are no instances currently available`
- Outcome: could not allocate

### 5. 4x H100 NVL

| Field | Value |
| --- | --- |
| Pod ID | `j6q4iu80tj922e` |
| Cost | `$10.36/hr` |
| Machine ID | `o7h99o28jtin` |
| Result | allocated |

Observed behavior:

- new machine ID, unlike the recycled RTX PRO 6000 community host
- SSH metadata appeared at `38.143.35.131:12908`
- direct SSH still returned `Connection refused`
- `uptimeSeconds` remained `0`

Outcome: allocates, but still dead before runtime.

### 6. 4x H200

- Status in inventory: low stock in some regions
- Result: `HTTP 500 There are no instances currently available`
- Outcome: could not allocate

### 7. 4x RTX PRO 6000 Secure

| Field | Value |
| --- | --- |
| Pod ID | `c3j21r1pd9wpa2` |
| Cost | `$7.56/hr` |
| Machine ID | `67fbuhb2qnz1` |
| Datacenter | `EUR-IS-1` |
| Result | allocated |

Observed behavior:

- first Secure RTX PRO 6000 host tested, so this was a different pool than the recycled dead community host
- SSH metadata appeared at `157.157.221.30:52123`
- direct SSH still returned `Connection refused`
- `uptimeSeconds` remained `0`

Outcome: cheapest allocatable NVIDIA path found today, but still dead before runtime.

## Practical Conclusion

As of 2026-04-25, the cheapest allocatable RunPod topology found for this model was:

- `2x MI300X` at `$3.98/hr`

The cheapest allocatable NVIDIA topology found was:

- `4x RTX PRO 6000 Secure` at `$7.56/hr`

Neither became reachable enough to run inference, so no successful benchmark could be produced from the cheap-first search.

## Cleanup

Every failed pod from this search was deleted after its readiness window.
