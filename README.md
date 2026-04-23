# GPU Deployment Experiments

Open experiment log for deploying and benchmarking large models on rented GPU infrastructure.

This repository is intentionally practical:

- `docs/research/` keeps deployment research and source notes.
- `experiments/` keeps runbooks, decisions, and run logs per experiment.
- `scripts/runpod/` creates, inspects, and tears down RunPod resources.
- `scripts/serve/` contains commands intended to run inside GPU pods.
- `scripts/benchmark/` contains OpenAI-compatible smoke and benchmark clients.
- `results/` is for benchmark outputs that are safe to publish.

Do not commit API keys, provider credentials, private model tokens, SSH keys, or raw logs that contain secrets. Use `.env` locally and keep secrets in environment variables.

## Experiments

`experiments/001-mi300x-kimi-k26/` tracks the initial AMD MI300X deployment of `moonshotai/Kimi-K2.6` on RunPod spot pods.

`experiments/002-kimi-k26-gguf-q2/` tracks the lower-VRAM GGUF route using `unsloth/Kimi-K2.6-GGUF` with llama.cpp.

Current full-precision preferred path:

1. Use a RunPod Secure Cloud MI300X pod because MI300X availability is currently Secure Cloud only.
2. Use an interruptible/spot pod through the RunPod REST API with `interruptible: true`.
3. Attach a network volume in the same datacenter so model weights and benchmark artifacts survive spot eviction and pod termination.
4. Serve Kimi K2.6 with SGLang on 4x MI300X first, because the SGLang Kimi K2.6 cookbook gives AMD-specific MI300X guidance.
5. Validate with a smoke prompt, then run controlled concurrency benchmarks.

Current low-VRAM fallback path:

1. Use `unsloth/Kimi-K2.6-GGUF` `UD-Q2_K_XL`, which is materially smaller than the full BF16 checkpoint.
2. Rank RunPod GPU nodes by enough aggregate VRAM for the quantized model, then prefer the cheapest spot configuration.
3. Serve with llama.cpp, validate its OpenAI-compatible endpoint, then run the same benchmark client.

## Quick Start

```bash
cp .env.example .env
# Fill RUNPOD_API_KEY locally, then:
source .env

scripts/runpod/check_availability.sh

# Optional, creates billable persistent storage.
scripts/runpod/create_network_volume.sh

# Creates a billable spot pod. Set NETWORK_VOLUME_ID first if using one.
scripts/runpod/create_spot_pod_rest.sh
```

Use `DRY_RUN=1` with the create scripts to inspect settings without creating billable resources.
`create_spot_pod_rest.sh` requires `NETWORK_VOLUME_ID` by default. Set `ALLOW_POD_VOLUME=1` only for disposable tests where a normal pod volume is acceptable.
If the REST API rejects a CLI-configured API key or explicit spot bidding is needed, use `scripts/runpod/create_spot_pod_graphql.sh`.
That script also supports disposable pod volumes for capacity probes with `ALLOW_POD_VOLUME=1`.

After the server is reachable:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install openai

python scripts/benchmark/smoke_openai.py \
  --base-url "http://YOUR_POD_HOST:30000/v1" \
  --model "moonshotai/Kimi-K2.6"

python scripts/benchmark/benchmark_openai.py \
  --base-url "http://YOUR_POD_HOST:30000/v1" \
  --model "moonshotai/Kimi-K2.6" \
  --requests 16 \
  --concurrency 4 \
  --output results/001-mi300x-kimi-k26-smoke.jsonl
```

## License

Repository scripts and documentation are MIT licensed. Model weights, model code, and provider services remain governed by their own licenses and terms.
