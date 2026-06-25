#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../edge/validate_caddy_redirect.py"
SYNC_SCRIPT="$SCRIPT_DIR/../edge/sync_caddyfile.sh"
BOUNDARY_SCRIPT="$SCRIPT_DIR/../edge/check_admin_boundary.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])


def fixture(location):
    return {
        "apps": {
            "http": {
                "servers": {
                    "srv": {
                        "routes": [
                            {
                                "match": [{"path": ["/api"]}],
                                "handle": [
                                    {
                                        "handler": "static_response",
                                        "status_code": 308,
                                        "headers": {"Location": [location]},
                                    }
                                ],
                            }
                        ]
                    }
                }
            }
        }
    }

(root / "good.json").write_text(json.dumps(fixture("/api/")), encoding="utf-8")
(root / "wrong.json").write_text(json.dumps(fixture("/wrong/")), encoding="utf-8")
PY

python3 "$VALIDATOR" --adapted-json "$TMP/good.json" | grep -q 'CADDY_REDIRECT_CONTRACT=PASS'

set +e
out="$(python3 "$VALIDATOR" --adapted-json "$TMP/wrong.json" 2>&1)"
rc=$?
set -e

[[ $rc -eq 1 ]] || {
  echo "expected rc=1, got $rc"
  exit 1
}
grep -qF 'expected exact 308 redirect from /api to /api/' <<<"$out"

python3 - "$SYNC_SCRIPT" "$BOUNDARY_SCRIPT" <<'PY'
from pathlib import Path
import sys

sync = Path(sys.argv[1]).read_text(encoding="utf-8")
boundary = Path(sys.argv[2]).read_text(encoding="utf-8")

required_sync = [
    "set -euo pipefail",
    "CANDIDATE_SNAPSHOT=",
    "SYNTAX_RC=$?",
    'python3 "$CADDY_CONTRACT_VALIDATOR" --caddyfile "$CANDIDATE_SNAPSHOT"',
    'python3 "$CADDY_REDIRECT_VALIDATOR" --caddyfile "$CANDIDATE_SNAPSHOT"',
    'cat "$CANDIDATE_SNAPSHOT" >"$LIVE_FILE"',
]
required_boundary = [
    'compose ps --quiet "$CADDY_SERVICE"',
    'docker inspect "$CADDY_CONTAINER_ID"',
    "http://127.0.0.1:2019/config/",
    "http://[::1]:2019/config/",
    'wget -qO- -T 3 "$url"',
    'curl --fail --silent --max-time 3 "$url"',
]

for needle in required_sync:
    if needle not in sync:
        raise SystemExit(f"missing sync hardening invariant: {needle}")
for forbidden in ('cat "$CANDIDATE_FILE" >"$LIVE_FILE"', 'docker inspect "$CADDY_CONTAINER"'):
    if forbidden in sync or forbidden in boundary:
        raise SystemExit(f"forbidden stale-path invariant present: {forbidden}")
for needle in required_boundary:
    if needle not in boundary:
        raise SystemExit(f"missing boundary hardening invariant: {needle}")
PY

echo "Edge redirect and hardening invariant tests passed"
