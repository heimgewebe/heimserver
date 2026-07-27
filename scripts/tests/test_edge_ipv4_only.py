#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOUNDARY = ROOT / "scripts" / "edge" / "check_admin_boundary.sh"
GOOD_ID = "0123456789abcdef" * 4

DOCKER = r'''#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
cmd = args[0]
rest = args[1:]
good_id = os.environ["GOOD_ID"]

if cmd == "compose":
    joined = " ".join(rest)
    if "ps --quiet" in joined:
        print(good_id)
        raise SystemExit(0)
    if "config --format json" in joined:
        print(json.dumps({"services": {"caddy": {"ports": []}}}))
        raise SystemExit(0)
    raise SystemExit(90)

if cmd == "exec":
    if rest[0] != good_id:
        raise SystemExit(91)
    joined = " ".join(rest[1:])
    if "cat /proc/net/tcp" in joined:
        print(os.environ["MOCK_PROC"])
    raise SystemExit(0)

if cmd == "inspect":
    if rest[0] != good_id:
        raise SystemExit(92)
    print("null")
    raise SystemExit(0)

raise SystemExit(93)
'''

SS = '''#!/usr/bin/env python3
print("LISTEN 0 128 0.0.0.0:80 0.0.0.0:*")
'''

ipv4 = '''  sl  local_address rem_address st
0: 0100007F:07E3 00000000:0000 0A
---TCP6---'''
mixed = ipv4 + '''
0: 00000000000000000000000001000000:07E3 00000000000000000000000000000000:0000 0A'''

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bindir = root / "bin"
    edgedir = root / "edge"
    bindir.mkdir()
    edgedir.mkdir()
    (edgedir / "docker-compose.yml").touch()

    docker = bindir / "docker"
    docker.write_text(DOCKER, encoding="utf-8")
    docker.chmod(0o755)
    ss = bindir / "ss"
    ss.write_text(SS, encoding="utf-8")
    ss.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bindir}:{env['PATH']}",
            "GOOD_ID": GOOD_ID,
            "EDGE_DIR": str(edgedir),
            "COMPOSE_FILE": str(edgedir / "docker-compose.yml"),
            "ALLOW_HISTORICAL_HOST_READ": "1",
        }
    )

    env["MOCK_PROC"] = ipv4
    ok = subprocess.run(
        ["bash", str(BOUNDARY), "--container-id", GOOD_ID],
        env=env,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if ok.returncode != 0:
        raise SystemExit(f"IPv4-only fixture failed: {ok.stderr}")

    env["MOCK_PROC"] = mixed
    rejected = subprocess.run(
        ["bash", str(BOUNDARY), "--container-id", GOOD_ID],
        env=env,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if rejected.returncode != 1:
        raise SystemExit(
            f"mixed IPv4/IPv6 listener returned {rejected.returncode}: "
            f"{rejected.stderr}"
        )

print("PASS: mixed IPv4/IPv6 listener is rejected")
