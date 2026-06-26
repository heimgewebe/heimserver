#!/usr/bin/env python3
"""Caddy contract test: delegates to the canonical validator."""
import subprocess
import sys
import os

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

result = subprocess.run(
    [
        sys.executable,
        os.path.join(repo_root, "scripts", "edge", "validate_caddy_contract.py"),
        "--caddyfile",
        os.path.join(repo_root, "edge", "Caddyfile.template"),
    ],
    check=False,
)
if result.returncode == 0:
    print("== All structural Caddyfile tests passed ==")
else:
    print(f"== Caddyfile contract FAILED (exit {result.returncode}) ==", file=sys.stderr)
sys.exit(result.returncode)
