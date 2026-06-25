#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../edge/validate_caddy_redirect.py"
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

echo "Edge redirect target tests passed"
