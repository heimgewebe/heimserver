#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYNC = ROOT / "scripts" / "edge" / "sync_caddyfile.sh"
GOOD_ID = "0123456789abcdef" * 4

DOCKER = r'''#!/usr/bin/env python3
import json
import os
import subprocess
import sys

args = sys.argv[1:]
cmd = args[0]
rest = args[1:]

if cmd == "image":
    raise SystemExit(0)
if cmd == "compose":
    if "ps" in rest and "--quiet" in rest:
        print(os.environ["GOOD_ID"])
        raise SystemExit(0)
    raise SystemExit(90)
if cmd == "exec":
    if rest[0] != os.environ["GOOD_ID"]:
        raise SystemExit(91)
    if "sha256sum" in rest:
        subprocess.run(["sha256sum", os.environ["LIVE_FILE"]], check=True)
    raise SystemExit(0)
if cmd == "run":
    joined = " ".join(rest)
    if "caddy validate" in joined:
        raise SystemExit(0)
    if "caddy adapt" in joined:
        print(json.dumps({"apps": {"http": {"servers": {}}}}))
        raise SystemExit(0)
    raise SystemExit(92)
raise SystemExit(93)
'''

CONTRACT = '''#!/usr/bin/env python3
import os
import sys
raise SystemExit(int(os.environ.get("MOCK_CONTRACT_RC", "0")) if "--adapted-json" in sys.argv else 2)
'''

BOUNDARY = '''#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--container-id" && "$2" == "$GOOD_ID" ]]
'''

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bindir = root / "bin"
    edgedir = root / "edge"
    candidate_dir = root / "repo" / "edge"
    bindir.mkdir()
    edgedir.mkdir()
    candidate_dir.mkdir(parents=True)

    live = edgedir / "Caddyfile"
    candidate = candidate_dir / "Caddyfile.template"
    live.write_text("same\n", encoding="utf-8")
    candidate.write_text("same\n", encoding="utf-8")
    (edgedir / "docker-compose.yml").touch()

    docker = bindir / "docker"
    docker.write_text(DOCKER, encoding="utf-8")
    docker.chmod(0o755)
    contract = root / "contract.py"
    contract.write_text(CONTRACT, encoding="utf-8")
    contract.chmod(0o755)
    boundary = root / "boundary.sh"
    boundary.write_text(BOUNDARY, encoding="utf-8")
    boundary.chmod(0o755)
    events = root / "events.log"

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bindir}:{env['PATH']}",
            "GOOD_ID": GOOD_ID,
            "EDGE_DIR": str(edgedir),
            "COMPOSE_FILE": str(edgedir / "docker-compose.yml"),
            "LIVE_FILE": str(live),
            "CANDIDATE_FILE": str(candidate),
            "LOCK_FILE": str(root / "sync.lock"),
            "CADDY_IMAGE": "caddy:2.8.4",
            "SYNC_EVENT_LOG": str(events),
            "CADDY_CONTRACT_VALIDATOR": str(contract),
            "ADMIN_BOUNDARY_CHECK": str(boundary),
        }
    )
    env["EXPECTED_LIVE_SHA256"] = subprocess.check_output(
        ["sha256sum", str(live)], text=True
    ).split()[0]

    ok = subprocess.run(["bash", str(SYNC)], env=env, check=False)
    if ok.returncode != 0:
        raise SystemExit(f"no-op proof returned {ok.returncode}")

    expected = [
        "snapshot",
        "syntax",
        "adapt",
        "contract",
        "boundary",
        "snapshot-recheck",
        "live-recheck",
        "container-recheck",
    ]
    if events.read_text(encoding="utf-8").splitlines() != expected:
        raise SystemExit("no-op skipped part of the proof chain")
    if list(edgedir.glob("Caddyfile.bak.*")):
        raise SystemExit("no-op created a backup")
    if live.read_text(encoding="utf-8") != "same\n":
        raise SystemExit("no-op modified the live file")

    events.write_text("", encoding="utf-8")
    env["MOCK_CONTRACT_RC"] = "1"
    rejected = subprocess.run(
        ["bash", str(SYNC)], env=env, check=False, stdout=subprocess.DEVNULL
    )
    if rejected.returncode != 1:
        raise SystemExit("no-op did not preserve contract failure")
    if list(edgedir.glob("Caddyfile.bak.*")):
        raise SystemExit("failed no-op created a backup")

print("PASS: no-op executes the full read-only proof chain")
