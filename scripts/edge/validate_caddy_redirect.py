#!/usr/bin/env python3
"""Validate the exact internal /api -> /api/ redirect in adapted Caddy JSON."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

CADDY_IMAGE = os.environ.get("CADDY_IMAGE", "caddy:2.8.4")


def die(code: int, message: str) -> None:
    label = "CONTRACT VIOLATION" if code == 1 else "DIAGNOSTIC FAILURE"
    print(f"{label}: {message}", file=sys.stderr)
    raise SystemExit(code)


def load_json(path: str) -> dict[str, Any]:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        die(2, f"cannot load adapted JSON: {exc}")


def adapt(path: str) -> dict[str, Any]:
    candidate = Path(path).resolve()
    try:
        result = subprocess.run(
            [
                "docker",
                "run",
                "--rm",
                "--pull=never",
                "--network",
                "none",
                "-v",
                f"{candidate.parent}:/candidate:ro",
                CADDY_IMAGE,
                "caddy",
                "adapt",
                "--adapter",
                "caddyfile",
                "--config",
                f"/candidate/{candidate.name}",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        die(2, "docker not found")
    if result.returncode != 0:
        die(2, f"caddy adapt failed (rc={result.returncode}): {result.stderr.strip()}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        die(2, f"caddy adapt output is invalid JSON: {exc}")


def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def direct_paths(route: dict[str, Any]) -> list[str]:
    paths: list[str] = []
    for matcher in route.get("match", []):
        if isinstance(matcher, dict):
            raw = matcher.get("path", [])
            if isinstance(raw, list):
                paths.extend(str(item) for item in raw)
    return paths


def exact_location(handler: dict[str, Any]) -> bool:
    if handler.get("handler") != "static_response":
        return False
    if handler.get("status_code") != 308:
        return False
    headers = handler.get("headers", {})
    if not isinstance(headers, dict):
        return False
    locations = [value for key, value in headers.items() if key.lower() == "location"]
    if len(locations) != 1:
        return False
    value = locations[0]
    normalized = value if isinstance(value, list) else [value]
    return normalized == ["/api/"]


def validate(data: dict[str, Any]) -> None:
    candidates: list[dict[str, Any]] = []
    for node in walk(data):
        if "/api" in direct_paths(node):
            candidates.append(node)
    if len(candidates) != 1:
        die(1, f"expected exactly one direct /api route, found {len(candidates)}")

    handlers = [node for node in walk(candidates[0]) if exact_location(node)]
    if len(handlers) != 1:
        die(1, "expected exact 308 redirect from /api to /api/")


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--caddyfile")
    group.add_argument("--adapted-json")
    args = parser.parse_args()
    data = adapt(args.caddyfile) if args.caddyfile else load_json(args.adapted_json)
    validate(data)
    print("CADDY_REDIRECT_CONTRACT=PASS")


if __name__ == "__main__":
    main()
