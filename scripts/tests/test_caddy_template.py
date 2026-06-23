#!/usr/bin/env python3
import json
import subprocess
import sys

TEMPLATE = "edge/Caddyfile.template"

def run_caddy_adapt():
    # Use stderr capture to not discard it
    result = subprocess.run([
        "docker", "run", "--rm", "--network", "none",
        "-v", f"{subprocess.getoutput('pwd')}:/repo:ro",
        "-w", "/repo", "caddy:2.8.4",
        "caddy", "adapt", "--adapter", "caddyfile", "--config", TEMPLATE
    ], capture_output=True, text=True)
    if result.returncode != 0:
        print("caddy adapt failed:")
        print(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)

data = run_caddy_adapt()

# Find servers
servers = data.get("apps", {}).get("http", {}).get("servers", {})
all_routes = []
for srv in servers.values():
    all_routes.extend(srv.get("routes", []))

def find_host_routes(hosts):
    matched = []
    for route in all_routes:
        matchers = route.get("match", [])
        for m in matchers:
            if "host" in m:
                if any(h in m["host"] for h in hosts):
                    matched.append(route)
    return matched

weltgewebe_routes = find_host_routes(["weltgewebe.net", "www.weltgewebe.net"])
api_weltgewebe_routes = find_host_routes(["api.weltgewebe.net"])

if not weltgewebe_routes:
    print("❌ MISSING: weltgewebe.net routes")
    sys.exit(1)

if not api_weltgewebe_routes:
    print("❌ MISSING: api.weltgewebe.net routes")
    sys.exit(1)

# Check weltgewebe.net routes
weltgewebe_str = json.dumps(weltgewebe_routes)
checks = {
    "Basemap": "/local-basemap/*",
    "API": "/api/*",
    "Health": "/health/*",
    "Assets": "/_app/immutable/*",
    "version.json": "/_app/version.json",
    "Cache": "Cache-Control",
    "Header": "Content-Security-Policy"
}

for desc, expected in checks.items():
    if expected not in weltgewebe_str:
        print(f"❌ MISSING in weltgewebe.net: {desc} ({expected})")
        sys.exit(1)
    else:
        print(f"✅ FOUND in weltgewebe.net: {desc}")

# Check api.weltgewebe.net routes
api_str = json.dumps(api_weltgewebe_routes)
if "weltgewebe-api:8080" not in api_str:
    print("❌ MISSING in api.weltgewebe.net: API Upstream (weltgewebe-api:8080)")
    sys.exit(1)
else:
    print("✅ FOUND in api.weltgewebe.net: API Upstream")

if "file_server" in api_str or "/srv/weltgewebe-web" in api_str:
    print("❌ UNEXPECTED in api.weltgewebe.net: file_server or static root")
    sys.exit(1)
else:
    print("✅ EXCLUDED in api.weltgewebe.net: file_server and static root")

# Negative tests
all_str = json.dumps(data)
negatives = ["weltweb.net", "www.weltweb.net", "weltweberei.org", "www.weltweberei.org"]
for neg in negatives:
    if neg in all_str:
        print(f"❌ UNEXPECTED: {neg}")
        sys.exit(1)
    else:
        print(f"✅ EXCLUDED globally: {neg}")

print("== All structural Caddyfile tests passed ==")
