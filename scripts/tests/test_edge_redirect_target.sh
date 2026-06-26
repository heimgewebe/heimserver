#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/edge/validate_caddy_contract.py"
TEMPLATE="$REPO_ROOT/edge/Caddyfile.template"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8.4}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$TEMPLATE" "$TMP/Caddyfile"

docker run \
  --rm \
  --pull=never \
  --network none \
  -v "$TMP:/candidate:ro" \
  "$CADDY_IMAGE" \
  caddy adapt \
    --adapter caddyfile \
    --config /candidate/Caddyfile \
  >"$TMP/baseline.json"

python3 "$VALIDATOR" --adapted-json "$TMP/baseline.json" >/dev/null

python3 - "$TMP/baseline.json" "$TMP" <<'PY'
import copy
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
data = json.loads(source.read_text(encoding="utf-8"))


def route_hosts(route):
    hosts = set()
    for matcher in route.get("match", []):
        hosts.update(matcher.get("host", []))
    return hosts


def route_paths(route):
    paths = []
    for matcher in route.get("match", []):
        paths.extend(matcher.get("path", []))
    return paths


def direct_children(route):
    children = []
    for handler in route.get("handle", []):
        if handler.get("handler") == "subroute":
            children.extend(handler.get("routes", []))
    return children


def internal_routes(doc):
    servers = doc.get("apps", {}).get("http", {}).get("servers", {})
    for server in servers.values():
        for host_route in server.get("routes", []):
            if route_hosts(host_route) == {"weltgewebe.home.arpa"}:
                children = direct_children(host_route)
                if any("/api" in route_paths(route) for route in children):
                    return children
    raise SystemExit("internal host route not found")


def api_redirect_route(doc):
    matches = [
        route
        for route in internal_routes(doc)
        if "/api" in route_paths(route)
    ]
    if len(matches) != 1:
        raise SystemExit(f"expected one internal /api route, found {len(matches)}")
    return matches[0]


def redirect_handler(route):
    handlers = [
        handler
        for handler in route.get("handle", [])
        if handler.get("handler") == "static_response"
    ]
    if len(handlers) != 1:
        raise SystemExit(f"expected one direct static_response, found {len(handlers)}")
    return handlers[0]


wrong_target = copy.deepcopy(data)
redirect_handler(api_redirect_route(wrong_target))["headers"]["Location"] = ["/wrong/"]

wrong_status = copy.deepcopy(data)
redirect_handler(api_redirect_route(wrong_status))["status_code"] = 307

foreign_host = copy.deepcopy(data)
redirect_handler(api_redirect_route(foreign_host))["headers"]["Location"] = ["/wrong/"]
servers = foreign_host["apps"]["http"]["servers"]
first_server = next(iter(servers.values()))
foreign_route = {
    "match": [{"host": ["redirect-decoy.home.arpa"]}],
    "handle": [
        {
            "handler": "subroute",
            "routes": [
                {
                    "match": [{"path": ["/api"]}],
                    "handle": [
                        {
                            "handler": "static_response",
                            "status_code": 308,
                            "headers": {"Location": ["/api/"]},
                        }
                    ],
                }
            ],
        }
    ],
}
first_server.setdefault("routes", []).append(foreign_route)

for name, doc in {
    "wrong-target.json": wrong_target,
    "wrong-status.json": wrong_status,
    "foreign-host-decoy.json": foreign_host,
}.items():
    (out_dir / name).write_text(
        json.dumps(doc, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
PY

for mutant in wrong-target wrong-status foreign-host-decoy; do
  set +e
  out="$(python3 "$VALIDATOR" --adapted-json "$TMP/$mutant.json" 2>&1 >/dev/null)"
  rc=$?
  set -e
  if [[ $rc -ne 1 ]]; then
    echo "expected $mutant to fail with rc=1, got rc=$rc" >&2
    echo "$out" >&2
    exit 1
  fi
  grep -qF "Internal API redirect" <<<"$out" || {
    echo "expected $mutant failure to come from host-bound redirect contract" >&2
    echo "$out" >&2
    exit 1
  }
done

echo "Edge redirect target contract tests passed"
