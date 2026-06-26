#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "edge" / "validate_compose_contract.py"

MOCK = '''#!/usr/bin/env python3
import json
import sys

if "config" not in sys.argv or "--format" not in sys.argv:
    raise SystemExit(90)

print(json.dumps({
    "services": {
        "caddy": {
            "image": "caddy:2.8.4",
            "container_name": "edge-caddy",
            "ports": [
                {"published": 80, "target": 80, "protocol": "tcp"},
                {"published": 443, "target": 443, "protocol": "tcp"}
            ],
            "networks": {"edge": {}, "heimnet": {}, "weltgewebe_default": {}},
            "volumes": [
                {"type": "bind", "source": "/tmp/Caddyfile", "target": "/etc/caddy/Caddyfile", "read_only": True},
                {"type": "bind", "source": "/opt/weltgewebe/apps/web/build", "target": "/srv/weltgewebe-web", "read_only": True},
                {"type": "bind", "source": "/opt/weltgewebe/build/basemap", "target": "/srv/weltgewebe-basemap", "read_only": True},
                {"type": "bind", "source": "/opt/weltgewebe/map-style", "target": "/srv/weltgewebe-map-style", "read_only": True},
                {"type": "volume", "source": "caddy_data", "target": "/data"},
                {"type": "volume", "source": "caddy_config", "target": "/config"}
            ]
        }
    },
    "networks": {
        "edge": {"external": True},
        "heimnet": {"external": True},
        "weltgewebe_default": {"external": True}
    },
    "volumes": {
        "caddy_data": {"name": "edge_caddy_data"},
        "caddy_config": {"name": "edge_caddy_config"}
    }
}))
print("mock compose warning on stderr", file=sys.stderr)
'''

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bindir = root / "bin"
    bindir.mkdir()
    docker = bindir / "docker"
    docker.write_text(MOCK, encoding="utf-8")
    docker.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{bindir}:{env['PATH']}"
    result = subprocess.run(
        ["docker", "compose", "config", "--format", "json"],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"mock compose failed with rc={result.returncode}")
    json.loads(result.stdout)
    if "mock compose warning on stderr" not in result.stderr:
        raise SystemExit("stderr warning was not captured separately")

    rendered = root / "compose.json"
    rendered.write_text(result.stdout, encoding="utf-8")
    validation = subprocess.run(
        ["python3", str(VALIDATOR), "--service", "caddy", "--json", str(rendered)],
        check=False,
        capture_output=True,
        text=True,
    )
    if validation.returncode != 0:
        raise SystemExit(validation.stderr or validation.stdout)

print("PASS: valid Compose stdout remains parseable with real stderr output")
