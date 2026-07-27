#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYNC = ROOT / "scripts" / "edge" / "sync_caddyfile.sh"


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bindir = root / "bin"
    bindir.mkdir()

    live = root / "Caddyfile"
    candidate = root / "Caddyfile.template"
    lock = root / "sync.lock"
    docker_log = root / "docker.log"
    live.write_text("same\n", encoding="utf-8")
    candidate.write_text("same\n", encoding="utf-8")

    docker = bindir / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\n"
        'printf "unexpected docker call\\n" >>"${DOCKER_LOG:?}"\n'
        "exit 99\n",
        encoding="utf-8",
    )
    docker.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bindir}:{env['PATH']}",
            "DOCKER_LOG": str(docker_log),
            "LIVE_FILE": str(live),
            "CANDIDATE_FILE": str(candidate),
            "LOCK_FILE": str(lock),
            "EXPECTED_LIVE_SHA256": subprocess.check_output(
                ["sha256sum", str(live)],
                text=True,
            ).split()[0],
        }
    )

    blocked = subprocess.run(
        ["bash", str(SYNC)],
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if blocked.returncode != 2:
        raise SystemExit(f"retired no-op returned {blocked.returncode}")
    if "Blocked: Heimserver is retired" not in blocked.stdout:
        raise SystemExit("retired no-op did not emit the retirement marker")
    if live.read_text(encoding="utf-8") != "same\n":
        raise SystemExit("retired no-op modified the live fixture")
    if candidate.read_text(encoding="utf-8") != "same\n":
        raise SystemExit("retired no-op modified the candidate fixture")
    if lock.exists() or docker_log.exists():
        raise SystemExit("retired no-op performed work before its guard")
    if list(root.glob("Caddyfile.bak.*")):
        raise SystemExit("retired no-op created a backup")

print("PASS: even a no-op Caddy sync is blocked before host access")
