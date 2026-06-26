#!/usr/bin/env python3
"""Structural Docker Compose contract validator.

Reads rendered Compose config JSON from stdin or ``--json``.

Exit codes:
    0 — contract satisfied
    1 — contract violation
    2 — diagnosis not possible (bad input / parse failure)
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


EXPECTED_IMAGE = "caddy:2.8.4"
EXPECTED_NETWORKS = {"edge", "heimnet", "weltgewebe_default"}
EXPECTED_PORTS = {(80, 80, "tcp"), (443, 443, "tcp")}
REQUIRED_READONLY_BINDS = {
    "/srv/weltgewebe-web": "/opt/weltgewebe/apps/web/build",
    "/srv/weltgewebe-basemap": "/opt/weltgewebe/build/basemap",
    "/srv/weltgewebe-map-style": "/opt/weltgewebe/map-style",
}
CADDYFILE_BIND_TARGET = "/etc/caddy/Caddyfile"
REQUIRED_NAMED_VOLUMES = {
    "/data": "edge_caddy_data",
    "/config": "edge_caddy_config",
}


def die(code: int, msg: str) -> None:
    label = "CONTRACT VIOLATION" if code == 1 else "DIAGNOSTIC FAILURE"
    print(f"{label}: {msg}", file=sys.stderr)
    raise SystemExit(code)


def as_int(value: Any, label: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        die(2, f"Cannot parse {label}: {value!r}")


def load_data(path: str | None) -> dict[str, Any]:
    if path:
        try:
            raw = Path(path).read_text(encoding="utf-8")
        except OSError as exc:
            die(2, f"Cannot read JSON file: {exc}")
    else:
        raw = sys.stdin.read()

    if not raw.strip():
        die(2, "Empty input: no Compose JSON received")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(2, f"Compose JSON parse error: {exc}")

    if not isinstance(data, dict):
        die(2, "Compose JSON root must be an object")
    return data


def actual_volume_name(top_volumes: dict[str, Any], source: str) -> str:
    definition = top_volumes.get(source)
    if isinstance(definition, dict) and definition.get("name"):
        return str(definition["name"])
    return source


def normalized_volume(
    entry: Any,
    top_volumes: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    if isinstance(entry, dict):
        target = entry.get("target")
        if not target:
            die(2, f"Volume entry without target: {entry!r}")
        source = str(entry.get("source", ""))
        entry_type = str(
            entry.get("type", "volume" if source in top_volumes else "bind")
        )
        read_only = bool(
            entry.get("read_only")
            or entry.get("readonly")
            or entry.get("mode") == "ro"
        )
        return str(target), {
            "source": source,
            "actual_name": actual_volume_name(top_volumes, source),
            "type": entry_type,
            "read_only": read_only,
            "raw": entry,
        }

    if isinstance(entry, str):
        parts = entry.split(":")
        if len(parts) < 2:
            die(2, f"Cannot parse string volume entry: {entry!r}")
        source = parts[0]
        target = parts[1]
        mode = parts[2:] if len(parts) > 2 else []
        read_only = "ro" in mode
        entry_type = "volume" if source in top_volumes else "bind"
        return target, {
            "source": source,
            "actual_name": actual_volume_name(top_volumes, source),
            "type": entry_type,
            "read_only": read_only,
            "raw": entry,
        }

    die(2, f"Unknown volume format: {entry!r}")


def normalize_service_volumes(
    volumes: Any,
    top_volumes: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    if not isinstance(volumes, list):
        die(2, "Service volumes must be a list")

    result: dict[str, dict[str, Any]] = {}
    for entry in volumes:
        target, normalized = normalized_volume(entry, top_volumes)
        if target in result:
            die(1, f"Duplicate mount target: {target}")
        result[target] = normalized
    return result


def normalize_ports(ports: Any) -> set[tuple[int, int, str]]:
    if not isinstance(ports, list):
        die(2, "Service ports must be a list")

    mappings: set[tuple[int, int, str]] = set()
    for entry in ports:
        if isinstance(entry, dict):
            published = as_int(entry.get("published"), f"published port in {entry!r}")
            target = as_int(entry.get("target"), f"target port in {entry!r}")
            protocol = str(entry.get("protocol", "tcp"))
        elif isinstance(entry, str):
            raw = entry
            protocol = "tcp"
            if "/" in entry:
                entry, protocol = entry.rsplit("/", 1)
            parts = entry.split(":")
            if len(parts) == 1:
                die(1, f"Unpublished service port is not permitted: {raw!r}")
            published = as_int(parts[-2], f"published port in {raw!r}")
            target = as_int(parts[-1], f"target port in {raw!r}")
        else:
            die(2, f"Unknown port format: {entry!r}")

        if published == 2019 or target == 2019:
            die(1, f"Port 2019 must not be published or targeted (found: {entry!r})")
        mapping = (published, target, protocol)
        if mapping in mappings:
            die(1, f"Duplicate port mapping: {entry!r}")
        mappings.add(mapping)
    return mappings


def service_network_names(networks: Any) -> set[str]:
    if isinstance(networks, dict):
        return set(networks)
    if isinstance(networks, list):
        return {str(item) for item in networks}
    if networks in (None, ""):
        return set()
    die(2, f"Unknown networks format: {networks!r}")


def require_readonly_bind(
    service_volumes: dict[str, dict[str, Any]],
    target: str,
    expected_source: str | None,
) -> None:
    volume = service_volumes.get(target)
    if volume is None:
        die(1, f"Missing required read-only mount at {target}")
    if volume["type"] != "bind":
        die(1, f"Mount at {target} must be a bind mount, got {volume['type']!r}")
    if not volume["read_only"]:
        die(1, f"Mount at {target} must be read-only")
    if expected_source is not None and volume["source"] != expected_source:
        die(
            1,
            f"Bind mounted at {target} must use source {expected_source!r}, "
            f"got {volume['source']!r}",
        )


def validate(data: dict[str, Any], service_name: str) -> None:
    services = data.get("services")
    if not isinstance(services, dict):
        die(2, "Compose JSON has no services object")

    if service_name not in services:
        die(1, f"Expected service {service_name!r}, found: {list(services)}")
    if len(services) != 1:
        die(1, f"Expected exactly 1 service, found: {list(services)}")

    service = services[service_name]
    if not isinstance(service, dict):
        die(2, f"Service {service_name!r} is not an object")
    print(f"OK service={service_name}")

    image = service.get("image")
    if image != EXPECTED_IMAGE:
        die(1, f"Caddy image must be {EXPECTED_IMAGE!r}, got {image!r}")
    print(f"OK image={EXPECTED_IMAGE}")

    container_name = service.get("container_name", "")
    if container_name != "edge-caddy":
        die(1, f"container_name must be 'edge-caddy', got: {container_name!r}")
    print("OK container_name=edge-caddy")

    if service.get("network_mode") == "host":
        die(1, "network_mode: host is not permitted")
    print("OK network_mode is not host")

    found_ports = normalize_ports(service.get("ports", []))
    if found_ports != EXPECTED_PORTS:
        die(1, f"Ports must be exactly {sorted(EXPECTED_PORTS)}, got {sorted(found_ports)}")
    print("OK ports=80/tcp,443/tcp only")

    networks = service_network_names(service.get("networks"))
    missing_networks = EXPECTED_NETWORKS - networks
    extra_networks = networks - EXPECTED_NETWORKS
    if missing_networks:
        die(1, f"Missing service networks: {sorted(missing_networks)}")
    if extra_networks:
        die(1, f"Unexpected service networks: {sorted(extra_networks)}")
    print("OK networks=edge,heimnet,weltgewebe_default")

    top_networks = data.get("networks", {})
    if not isinstance(top_networks, dict):
        die(2, "Top-level networks must be an object")
    missing_top_networks = EXPECTED_NETWORKS - set(top_networks)
    if missing_top_networks:
        die(1, f"Missing top-level networks: {sorted(missing_top_networks)}")

    top_volumes = data.get("volumes", {})
    if not isinstance(top_volumes, dict):
        die(2, "Top-level volumes must be an object")

    found_volume_names = {
        str(value.get("name", key)) if isinstance(value, dict) else key
        for key, value in top_volumes.items()
    }
    for name in found_volume_names:
        if "edge_edge_" in name:
            die(1, f"Volume has double-prefix name: {name!r}")

    service_volumes = normalize_service_volumes(service.get("volumes", []), top_volumes)

    require_readonly_bind(service_volumes, CADDYFILE_BIND_TARGET, None)
    for target, source in REQUIRED_READONLY_BINDS.items():
        require_readonly_bind(service_volumes, target, source)
    print("OK exact read-only bind mounts")

    for target, expected_name in REQUIRED_NAMED_VOLUMES.items():
        volume = service_volumes.get(target)
        if volume is None:
            die(1, f"Missing required volume mount at {target}")
        if volume["actual_name"] != expected_name:
            die(
                1,
                f"Volume mounted at {target} must resolve to {expected_name!r}, "
                f"got {volume['actual_name']!r}",
            )
        if volume["type"] != "volume":
            die(1, f"Mount at {target} must be a named volume, got {volume['type']!r}")
        if volume["read_only"]:
            die(1, f"Named volume mounted at {target} must remain writable")
    print("OK writable named volumes=/data,/config")

    print("OK all Compose contract checks passed")


def main() -> None:
    parser = argparse.ArgumentParser(description="Structural Compose contract validator")
    parser.add_argument("--json", metavar="PATH", help="Path to rendered compose JSON")
    parser.add_argument(
        "--service",
        default=os.environ.get("CADDY_SERVICE", "caddy"),
        help="Expected Caddy Compose service ID",
    )
    args = parser.parse_args()
    validate(load_data(args.json), args.service)


if __name__ == "__main__":
    main()
