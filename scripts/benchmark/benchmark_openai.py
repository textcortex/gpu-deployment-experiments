#!/usr/bin/env python3
"""Simple concurrent benchmark for OpenAI-compatible chat endpoints."""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import time
from pathlib import Path
from typing import Any

from openai import AsyncOpenAI


DEFAULT_PROMPTS = [
    "Write a concise Python function that checks whether a string is a palindrome.",
    "Summarize the tradeoffs between spot GPU instances and on-demand GPU instances.",
    "Given a web service with p95 latency spikes, list five debugging steps.",
    "Create a small SQL schema for tracking GPU benchmark runs.",
]


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((pct / 100) * (len(ordered) - 1))))
    return ordered[index]


def read_prompts(path: str | None) -> list[str]:
    if not path:
        return DEFAULT_PROMPTS
    prompts = []
    for line in Path(path).read_text().splitlines():
        stripped = line.strip()
        if stripped:
            prompts.append(stripped)
    if not prompts:
        raise ValueError(f"No prompts found in {path}")
    return prompts


async def run_one(
    client: AsyncOpenAI,
    *,
    model: str,
    prompt: str,
    request_id: int,
    max_tokens: int,
    temperature: float,
    top_p: float,
    instant: bool,
) -> dict[str, Any]:
    extra_body = {"chat_template_kwargs": {"thinking": False}} if instant else None
    started = time.perf_counter()
    try:
        response = await client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temperature,
            top_p=top_p,
            extra_body=extra_body,
        )
        elapsed = time.perf_counter() - started
        message = response.choices[0].message
        usage = response.usage.model_dump() if response.usage else {}
        output_tokens = int(usage.get("completion_tokens") or 0)
        return {
            "request_id": request_id,
            "ok": True,
            "latency_s": elapsed,
            "output_tokens": output_tokens,
            "total_tokens": int(usage.get("total_tokens") or 0),
            "chars": len(message.content or ""),
            "prompt": prompt,
            "error": None,
        }
    except Exception as exc:  # noqa: BLE001 - benchmark should record all failures.
        return {
            "request_id": request_id,
            "ok": False,
            "latency_s": time.perf_counter() - started,
            "output_tokens": 0,
            "total_tokens": 0,
            "chars": 0,
            "prompt": prompt,
            "error": repr(exc),
        }


async def main_async() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="moonshotai/Kimi-K2.6")
    parser.add_argument("--api-key", default="EMPTY")
    parser.add_argument("--requests", type=int, default=16)
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--max-tokens", type=int, default=1024)
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--top-p", type=float, default=0.95)
    parser.add_argument("--instant", action="store_true")
    parser.add_argument("--prompt-file")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    prompts = read_prompts(args.prompt_file)
    client = AsyncOpenAI(base_url=args.base_url, api_key=args.api_key, timeout=3600)
    semaphore = asyncio.Semaphore(args.concurrency)

    async def guarded(request_id: int) -> dict[str, Any]:
        async with semaphore:
            return await run_one(
                client,
                model=args.model,
                prompt=prompts[request_id % len(prompts)],
                request_id=request_id,
                max_tokens=args.max_tokens,
                temperature=args.temperature,
                top_p=args.top_p,
                instant=args.instant,
            )

    started = time.perf_counter()
    results = await asyncio.gather(*(guarded(i) for i in range(args.requests)))
    wall_s = time.perf_counter() - started

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w") as handle:
        for row in results:
            handle.write(json.dumps(row, sort_keys=True) + "\n")

    successes = [row for row in results if row["ok"]]
    latencies = [float(row["latency_s"]) for row in successes]
    output_tokens = sum(int(row["output_tokens"]) for row in successes)
    summary = {
        "requests": args.requests,
        "successes": len(successes),
        "errors": args.requests - len(successes),
        "wall_s": wall_s,
        "requests_per_s": len(successes) / wall_s if wall_s else 0,
        "output_tokens_per_s": output_tokens / wall_s if wall_s else 0,
        "latency_avg_s": statistics.mean(latencies) if latencies else 0,
        "latency_p50_s": percentile(latencies, 50),
        "latency_p95_s": percentile(latencies, 95),
        "output": str(output),
    }
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    asyncio.run(main_async())

