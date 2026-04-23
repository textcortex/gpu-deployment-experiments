# Kimi K2.6 Serving Framework Comparison

Date: 2026-04-23

## Primary Sources

- Moonshot Kimi K2.6 model card: https://huggingface.co/moonshotai/Kimi-K2.6
- Moonshot Kimi K2.6 deployment guide: https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/docs/deploy_guidance.md
- vLLM Kimi K2 recipe: https://docs.vllm.ai/projects/recipes/en/latest/moonshotai/Kimi-K2.html
- SGLang Kimi K2.6 cookbook: https://cookbook.sglang.io/autoregressive/Moonshotai/Kimi-K2.6
- KTransformers Kimi K2.5 guide: https://github.com/kvcache-ai/ktransformers/blob/main/doc/en/Kimi-K2.5.md
- KTransformers site: https://www.ktransformers.net/en
- TensorRT-LLM support matrix: https://nvidia.github.io/TensorRT-LLM/reference/support-matrix.html
- TensorRT-LLM Kimi K2 Thinking Blackwell guide: https://nvidia.github.io/TensorRT-LLM/deployment-guide/deployment-guide-for-kimi-k2-thinking-on-trtllm.html

## Official Support Summary

Moonshot's Kimi K2.6 deployment guide officially recommends these engines:

- `vLLM`
- `SGLang`
- `KTransformers`

Moonshot does not list `TensorRT-LLM` in the K2.6 deployment guide. NVIDIA does have a TensorRT-LLM deployment guide for `Kimi-K2-Thinking` on Blackwell, but Kimi K2.6 is not named in Moonshot's K2.6 guide and is not listed in NVIDIA's TensorRT-LLM supported model matrix. Treat TensorRT-LLM for K2.6 as adjacent or experimental rather than the primary deployment path.

## Expected Performance Ranking

This ranking is an inference from the primary-source docs above, not a result from our own benchmark yet:

1. `vLLM`: best first pure-GPU throughput baseline
2. `SGLang`: likely close to vLLM on pure-GPU throughput, and the best AMD path
3. `TensorRT-LLM`: likely strongest top-end performance on supported Blackwell Kimi variants, but not a clean K2.6 baseline today
4. `KTransformers`: best low-VRAM or CPU+GPU heterogeneous option, but not the fastest pure-GPU route

## Why This Ranking

### vLLM

- Moonshot explicitly recommends it for K2.6.
- vLLM publishes concrete Kimi benchmark outputs and tuning guidance for high-throughput scenarios such as expert parallelism and decode-context parallelism.
- In the published H200 example for Kimi K2, vLLM reports `339.38 tok/s` output throughput after adding `-dcp 8`.

This makes vLLM the cleanest first candidate for a throughput-focused benchmark.

### SGLang

- Moonshot explicitly recommends it for K2.6.
- Moonshot's deployment guide says stable `SGLang >= 0.5.10.post1` is sufficient for K2.6.
- SGLang is the path Moonshot points to for AMD MI300X deployment in the K2.6 cookbook.

SGLang is the right second baseline and the first framework to use when we go back to AMD.

### KTransformers

- Moonshot explicitly recommends it for K2.6, but the deployment model is CPU+GPU heterogeneous and powered by SGLang.
- Moonshot's example for K2.6 reports `640.12 tokens/s` prefill and `24.51 tokens/s` decode at 48-way concurrency on `8x NVIDIA L20 + 2x Intel 6454S`.
- KTransformers is designed to lower VRAM requirements by leaning on CPU RAM and CPU inference.

That makes it valuable for deployability and cost avoidance, but not the first choice when raw decode speed on enough GPUs is the main goal.

### TensorRT-LLM

- NVIDIA now publishes a Kimi K2 Thinking deployment guide on Blackwell hardware.
- NVIDIA's own support matrix still does not list Kimi in the supported model matrix.
- The published guide is specifically for `nvidia/Kimi-K2-Thinking-NVFP4` on Blackwell, not Moonshot's Kimi K2.6 checkpoint.

TensorRT-LLM may become the fastest route on supported Blackwell Kimi variants, but it is not the best apples-to-apples comparison target for K2.6 on RunPod today.

## Practical Recommendation

When RunPod gives us a genuinely reachable node, use this order:

1. `vLLM` on a large NVIDIA node for the first full-GPU throughput baseline
2. `SGLang` on the same class of NVIDIA node for the second baseline
3. `KTransformers` only after those two, unless the node has insufficient VRAM for the full checkpoint
4. `TensorRT-LLM` only on Blackwell if we explicitly pivot to the NVIDIA Kimi K2 Thinking path

## Blocking Constraint Today

On 2026-04-23, RunPod on-demand capacity did eventually allocate several large nodes, but the allocated pods did not become actually reachable over SSH/HTTP before cleanup. That prevented an empirical framework benchmark on RunPod today.
