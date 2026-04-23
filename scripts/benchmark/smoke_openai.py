#!/usr/bin/env python3
"""Small OpenAI-compatible smoke test for Kimi K2.6 deployments."""

from __future__ import annotations

import argparse
from openai import OpenAI


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True, help="Example: http://host:30000/v1")
    parser.add_argument("--model", default="moonshotai/Kimi-K2.6")
    parser.add_argument("--api-key", default="EMPTY")
    parser.add_argument("--instant", action="store_true", help="Disable thinking mode.")
    parser.add_argument("--max-tokens", type=int, default=1024)
    args = parser.parse_args()

    client = OpenAI(base_url=args.base_url, api_key=args.api_key, timeout=3600)
    extra_body = {"chat_template_kwargs": {"thinking": False}} if args.instant else None

    response = client.chat.completions.create(
        model=args.model,
        messages=[{"role": "user", "content": "Which number is bigger, 9.11 or 9.9? Answer briefly."}],
        temperature=0.6 if args.instant else 1.0,
        top_p=0.95,
        max_tokens=args.max_tokens,
        extra_body=extra_body,
    )

    message = response.choices[0].message
    reasoning = getattr(message, "reasoning_content", None) or getattr(message, "reasoning", None)
    if reasoning:
        print("=== reasoning ===")
        print(reasoning)
    print("=== content ===")
    print(message.content)
    if response.usage:
        print("=== usage ===")
        print(response.usage.model_dump_json(indent=2))


if __name__ == "__main__":
    main()

