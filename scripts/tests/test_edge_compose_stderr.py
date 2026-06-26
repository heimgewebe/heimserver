#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPOSE_TEST = ROOT / "scripts" / "tests" / "test_edge_compose_contract.sh"

DOCKER = r'''#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
if args and args[0] == "compose" and "config" in args and "--format" in args:
    data = {
        "services": {
            "caddy": {
                "image": "caddy:2.8.4",
                "container_name": "edge-caddy",
                "ports": [
                    {"published": 80, "target": 80, "protocol": "tcp"},
                    {"published": 443, "target": 443, "protocol": "tcp"},
                ],
                "networks": {
                    "edge": {},
                    "heimnet": {},
                    "weltgewebe_default": {},
                },
                "volumes": [
                    {
                        "type": "bind",
                        "source": "/tmp/Caddyfile",
                        "target": "/etc/caddy/Caddyfile",
                        "read_only": True,
                    },
                    {
                        "type": "bind",
                        "source": "/opt/weltgewebe/apps/web/build",
                        "target": "/srv/weltgewebe-web",
                        "read_only": True,
                    },
                    {
                        "type": "bind",
                        "source": "/opt/weltgewebe/build/basemap",
                        "target": "/srv/weltgewebe-basemap",
                        "read_only": True,
                    },
                    {
                        "type": "bind",
                        "source": "/opt/weltgewebe/map-style",
                        "target": "/srv/weltgewebe-map-style",
                        "read_only": True,
                    },
                    {"type": "volume", "source": "caddy_data", "target": "/data"},
                    {"type": "volume", "source": "caddy_config", "target": "/config"},
                ],
            }
        },
        "networks": {
            "edge": {"external": True},
            "heimnet": {"external": True},
            "weltgewebe_default": {"external": True},
        },
        "volumes": {
            "caddy_data": {"name": "edge_caddy_data"},
            "caddy_config": {"name": "edge_caddy_config"},
        },
    }
    print(json.dumps(data))
    print("mock compose warning on stderr", file=sys.stderr)
    raise SystemExit(0)

raise SystemExit(99)
'''

with tempfile.TemporaryDirectory() as tmp:
    bindir = Path(tmp) / "bin"
    bindir.mkdir()
    docker = bindir / "docker"
    docker.write_text(DOCKER, encoding="utf-8")
    docker.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{bindir}:{env['PATH']}"
    env["CADDY_SERVICE"] = "caddy"

    result = subprocess.run(
        ["bash", str(COMPOSE_TEST)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    combined = result.stdout + result.stderr
    if result.returncode != 0:
        raise SystemExit(
            f"compose stderr regression failed with {result.returncode}: "
            f"{combined}"
        )
    if "mock compose warning on stderr" not in combined:
        raise SystemExit("real stderr warning was not observed")

print("PASS: valid Compose stdout remains parseable with real stderr output")
