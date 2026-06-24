#!/usr/bin/env python3
"""
validate_compose_contract.py — Structural Docker Compose contract validator.

Reads the rendered Compose config JSON from stdin or --json argument.

Usage:
    docker compose ... config --format json | python3 scripts/edge/validate_compose_contract.py
    python3 scripts/edge/validate_compose_contract.py --json /path/to/config.json

Exit codes:
    0 — contract satisfied
    1 — contract violation
    2 — diagnosis not possible (bad input / parse failure)
"""
import argparse
import json
import sys
from typing import Any


def die(code: int, msg: str) -> None:
    print(f"{'CONTRACT VIOLATION' if code == 1 else 'DIAGNOSTIC FAILURE'}: {msg}", file=sys.stderr)
    sys.exit(code)


def main() -> None:
    parser = argparse.ArgumentParser(description="Structural Compose contract validator")
    parser.add_argument("--json", metavar="PATH", help="Path to rendered compose JSON (default: stdin)")
    args = parser.parse_args()

    if args.json:
        try:
            with open(args.json) as f:
                raw = f.read()
        except OSError as e:
            die(2, f"Cannot read JSON file: {e}")
    else:
        raw = sys.stdin.read()

    if not raw.strip():
        die(2, "Empty input — no Compose JSON received")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        die(2, f"Compose JSON parse error: {e}")

    services = data.get("services", {})

    # ── 1. Exactly one service: caddy ─────────────────────────────────────────
    if "caddy" not in services:
        die(1, f"Expected service 'caddy', found: {list(services.keys())}")
    if len(services) != 1:
        die(1, f"Expected exactly 1 service, found: {list(services.keys())}")

    caddy = services["caddy"]
    print("✅ Exactly one service: caddy")

    # ── 2. container_name == edge-caddy ───────────────────────────────────────
    container_name = caddy.get("container_name", "")
    if container_name != "edge-caddy":
        die(1, f"container_name must be 'edge-caddy', got: {container_name!r}")
    print("✅ container_name=edge-caddy")

    # ── 3. No network_mode: host ──────────────────────────────────────────────
    net_mode = caddy.get("network_mode", "")
    if net_mode == "host":
        die(1, "network_mode: host is not permitted")
    print("✅ No network_mode: host")

    # ── 4. Exactly port 80→80 and 443→443 (tcp), nothing else ────────────────
    ports = caddy.get("ports", [])

    required_mappings = {
        (80, 80, "tcp"),
        (443, 443, "tcp"),
    }
    found_mappings = set()
    seen_published = []

    for p in ports:
        if isinstance(p, dict):
            published = p.get("published")
            target = p.get("target")
            protocol = p.get("protocol", "tcp")
            try:
                pub_int = int(published) if published is not None else None
                tgt_int = int(target) if target is not None else None
            except (TypeError, ValueError):
                die(2, f"Cannot parse port mapping: {p}")

            if pub_int == 2019:
                die(1, f"Port 2019 must not be published (found: {p})")

            mapping = (pub_int, tgt_int, protocol)
            if mapping in found_mappings:
                die(1, f"Duplicate port mapping: {p}")
            found_mappings.add(mapping)
            seen_published.append(pub_int)

        elif isinstance(p, str):
            # e.g. "80:80" or "80:80/tcp"
            raw_p = p
            protocol = "tcp"
            if "/" in p:
                p, protocol = p.rsplit("/", 1)
            parts = p.split(":")
            if len(parts) == 2:
                try:
                    pub_int = int(parts[0])
                    tgt_int = int(parts[1])
                except ValueError:
                    die(2, f"Cannot parse string port mapping: {raw_p}")
                if pub_int == 2019:
                    die(1, f"Port 2019 must not be published (found: {raw_p})")
                mapping = (pub_int, tgt_int, protocol)
                if mapping in found_mappings:
                    die(1, f"Duplicate port mapping: {raw_p}")
                found_mappings.add(mapping)
                seen_published.append(pub_int)
        else:
            die(2, f"Unknown port format: {p!r}")

    missing = required_mappings - found_mappings
    if missing:
        die(1, f"Missing required port mappings: {missing}")

    extra = found_mappings - required_mappings
    if extra:
        die(1, f"Unexpected port mappings (only 80→80 and 443→443 tcp allowed): {extra}")

    print("✅ Ports: exactly 80→80/tcp and 443→443/tcp, no others, no 2019")

    # ── 5. Volume names: edge_caddy_data and edge_caddy_config ───────────────
    top_volumes = data.get("volumes", {})
    required_volumes = {"edge_caddy_data", "edge_caddy_config"}

    # Check from the top-level volumes section
    found_vol_names = set()
    for vol_key, vol_def in top_volumes.items():
        vol_name = vol_def.get("name", "") if isinstance(vol_def, dict) else ""
        found_vol_names.add(vol_name)

    # Also check service-level volume references
    svc_volumes = caddy.get("volumes", [])
    for v in svc_volumes:
        if isinstance(v, dict):
            source = v.get("source", "")
            # source refers to the key in top-level volumes
            if source:
                # resolve actual name
                resolved = top_volumes.get(source, {})
                if isinstance(resolved, dict):
                    actual_name = resolved.get("name", source)
                    found_vol_names.add(actual_name)
        elif isinstance(v, str) and ":" in v:
            source = v.split(":")[0]
            resolved = top_volumes.get(source, {})
            if isinstance(resolved, dict):
                actual_name = resolved.get("name", source)
                found_vol_names.add(actual_name)

    missing_vols = required_volumes - found_vol_names
    if missing_vols:
        die(1, f"Missing required volume names: {missing_vols}")

    # Check no double-prefix names
    for name in found_vol_names:
        if "edge_edge_" in name:
            die(1, f"Volume has double-prefix name: {name!r}")

    print("✅ Volume names: edge_caddy_data and edge_caddy_config present, no double-prefix")

    print("✅ All Compose contract checks passed")


if __name__ == "__main__":
    main()
