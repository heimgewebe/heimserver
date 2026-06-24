#!/usr/bin/env python3
import json
import subprocess
import sys

TEMPLATE = "edge/Caddyfile.template"

print("Validating template with caddy validate...")
val_result = subprocess.run([
    "docker", "run", "--rm", "--network", "none",
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
    "docker", "run", "--rm", "--network", "none",
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

def find_route_with_exact_hosts(expected_hosts: set):
    for route in all_routes:
        for matcher in route.get("match", []):
            if set(matcher.get("host", [])) == expected_hosts:
                return route
    return None

web_route = find_route_with_exact_hosts({"weltgewebe.net", "www.weltgewebe.net"})
api_route = find_route_with_exact_hosts({"api.weltgewebe.net"})

if not web_route:
    print("❌ MISSING: exact host matches for weltgewebe.net and www.weltgewebe.net")
    sys.exit(1)

if not api_route:
    print("❌ MISSING: exact host matches for api.weltgewebe.net")
    sys.exit(1)

web_str = json.dumps(web_route)

# Semantic validations
print("--- Web Host Semantic Validations ---")
if '"dial": "weltgewebe-api:8080"' not in web_str:
    print("❌ MISSING in web host: API Upstream (weltgewebe-api:8080)")
    sys.exit(1)

if '"root": "/srv/weltgewebe-basemap"' not in web_str:
    print("❌ MISSING in web host: PMTiles / local-basemap root")
    sys.exit(1)

if '"root": "/srv/weltgewebe-map-style"' not in web_str:
    print("❌ MISSING in web host: Map-style root")
    sys.exit(1)

if '"public, max-age=31536000, immutable"' not in web_str:
    print("❌ MISSING: Immutable Cache-Control")
    sys.exit(1)
if '"no-store"' not in web_str:
    print("❌ MISSING: version.json no-store Cache-Control")
    sys.exit(1)
if '"no-cache, must-revalidate"' not in web_str:
    print("❌ MISSING: Default no-cache Cache-Control")
    sys.exit(1)

if '"Access-Control-Allow-Origin"' not in web_str or '"status_code": 204' not in web_str:
    print("❌ MISSING: CORS headers and OPTIONS 204")
    sys.exit(1)

print("✅ Web Host Semantic Validations Passed")

print("--- API Host Semantic Validations ---")
api_str = json.dumps(api_route)
if '"dial": "weltgewebe-api:8080"' not in api_str:
    print("❌ MISSING in api host: API Upstream (weltgewebe-api:8080)")
    sys.exit(1)

if "file_server" in api_str or "/srv/" in api_str:
    print("❌ UNEXPECTED in api host: static file server or root mounts")
    sys.exit(1)
print("✅ API Host Semantic Validations Passed")

print("--- Negative Tests ---")
all_str = json.dumps(data)
negatives = ["weltweb.net", "www.weltweb.net", "weltweberei.org", "www.weltweberei.org"]
for neg in negatives:
    if neg in all_str:
        print(f"❌ UNEXPECTED globally: {neg}")
        sys.exit(1)

internal_hosts = ["leitstand.heimgewebe.home.arpa", "weltgewebe.home.arpa", "api.weltgewebe.home.arpa"]
for internal in internal_hosts:
    if internal not in all_str:
        print(f"❌ MISSING INTERNAL HOST: {internal}")
        sys.exit(1)

print("✅ Negative Tests Passed")
print("== All structural Caddyfile tests passed ==")
