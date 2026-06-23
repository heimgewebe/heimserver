#!/usr/bin/env python3
import json
import subprocess
import sys

TEMPLATE = "edge/Caddyfile.template"

print("Validating template with caddy validate...")
val_result = subprocess.run([
    "docker", "run", "--rm", "--pull=never", "--network", "none",
    "-v", f"{subprocess.getoutput('pwd')}:/repo:ro",
    "-w", "/repo", "caddy:2.8.4",
    "caddy", "validate", "--adapter", "caddyfile", "--config", TEMPLATE
], capture_output=True, text=True)
if val_result.returncode != 0:
    print("caddy validate failed:")
    print(val_result.stderr)
    sys.exit(1)

print("Adapting template to JSON...")
result = subprocess.run([
    "docker", "run", "--rm", "--pull=never", "--network", "none",
    "-v", f"{subprocess.getoutput('pwd')}:/repo:ro",
    "-w", "/repo", "caddy:2.8.4",
    "caddy", "adapt", "--adapter", "caddyfile", "--config", TEMPLATE
], capture_output=True, text=True)
if result.returncode != 0:
    print("caddy adapt failed:")
    print(result.stderr)
    sys.exit(1)

data = json.loads(result.stdout)

servers = data.get("apps", {}).get("http", {}).get("servers", {})
all_routes = []
for srv in servers.values():
    all_routes.extend(srv.get("routes", []))

def find_host_routes(expected_hosts, exact_match=False):
    matched = []
    found_hosts = set()
    for route in all_routes:
        matchers = route.get("match", [])
        for m in matchers:
            if "host" in m:
                # Add found hosts to our set if they intersect
                route_hosts = set(m["host"])
                if set(expected_hosts).intersection(route_hosts):
                    found_hosts.update(route_hosts)
                    matched.append(route)
    if exact_match and not set(expected_hosts).issubset(found_hosts):
        return []
    return matched

required_web_hosts = ["weltgewebe.net", "www.weltgewebe.net"]
weltgewebe_routes = find_host_routes(required_web_hosts, exact_match=True)

api_required_hosts = ["api.weltgewebe.net"]
api_weltgewebe_routes = find_host_routes(api_required_hosts, exact_match=True)

if not weltgewebe_routes:
    print("❌ MISSING: exact host matches for weltgewebe.net and www.weltgewebe.net")
    sys.exit(1)

if not api_weltgewebe_routes:
    print("❌ MISSING: exact host matches for api.weltgewebe.net")
    sys.exit(1)

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

# Assertion for existing internal hosts
internal_hosts = ["leitstand.heimgewebe.home.arpa", "weltgewebe.home.arpa", "api.weltgewebe.home.arpa"]
for internal in internal_hosts:
    if internal not in all_str:
        print(f"❌ MISSING INTERNAL HOST: {internal}")
        sys.exit(1)
    else:
        print(f"✅ FOUND INTERNAL HOST: {internal}")

print("== All structural Caddyfile tests passed ==")
