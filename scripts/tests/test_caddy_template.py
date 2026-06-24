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

# Admin config check
admin_config = data.get("admin", {})
if admin_config.get("disabled", False) or "admin" not in data:
    print("❌ Caddy admin must remain loopback-only for the documented reload workflow")
    sys.exit(1)

admin_listen = admin_config.get("listen", "")
if admin_listen not in ["localhost:2019", "127.0.0.1:2019", "[::1]:2019", "tcp/localhost:2019", "tcp/127.0.0.1:2019", "tcp/[::1]:2019"]:
    print(f"❌ Caddy admin must remain loopback-only for the documented reload workflow. Found: {admin_listen}")
    sys.exit(1)


servers = data.get("apps", {}).get("http", {}).get("servers", {})
all_routes = []
for srv in servers.values():
    all_routes.extend(srv.get("routes", []))

def find_routes_with_exact_hosts(expected_hosts: set) -> list:
    routes = []
    for route in all_routes:
        for matcher in route.get("match", []):
            if set(matcher.get("host", [])) == expected_hosts:
                routes.append(route)
    return routes

# Public Web
web_routes = find_routes_with_exact_hosts({"weltgewebe.net", "www.weltgewebe.net"})
if not web_routes:
    print("❌ MISSING: exact host matches for weltgewebe.net and www.weltgewebe.net")
    sys.exit(1)

web_str = json.dumps(web_routes)
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
    print("❌ MISSING in web host: Immutable Cache-Control")
    sys.exit(1)
if '"no-store"' not in web_str:
    print("❌ MISSING in web host: version.json no-store Cache-Control")
    sys.exit(1)
if '"no-cache, must-revalidate"' not in web_str:
    print("❌ MISSING in web host: Default no-cache Cache-Control")
    sys.exit(1)

if '"Access-Control-Allow-Origin"' not in web_str or '"status_code": 204' not in web_str:
    print("❌ MISSING in web host: CORS headers and OPTIONS 204")
    sys.exit(1)

print("✅ Web Host Semantic Validations Passed")


# Internal Web
internal_routes = find_routes_with_exact_hosts({"weltgewebe.home.arpa"})
if not internal_routes:
    print("❌ MISSING: exact host matches for weltgewebe.home.arpa")
    sys.exit(1)

internal_str = json.dumps(internal_routes)
print("--- Internal Web Host Semantic Validations ---")
if '"dial": "weltgewebe-api:8080"' not in internal_str:
    print("❌ MISSING in internal host: API Upstream (weltgewebe-api:8080)")
    sys.exit(1)

if '"root": "/srv/weltgewebe-basemap"' not in internal_str:
    print("❌ MISSING in internal host: PMTiles / local-basemap root")
    sys.exit(1)

if '"root": "/srv/weltgewebe-map-style"' not in internal_str:
    print("❌ MISSING in internal host: Map-style root")
    sys.exit(1)

if '"public, max-age=31536000, immutable"' not in internal_str:
    print("❌ MISSING in internal host: Immutable Cache-Control")
    sys.exit(1)
if '"no-store"' not in internal_str:
    print("❌ MISSING in internal host: version.json no-store Cache-Control")
    sys.exit(1)
if '"no-cache, must-revalidate"' not in internal_str:
    print("❌ MISSING in internal host: Default no-cache Cache-Control")
    sys.exit(1)

if '"Access-Control-Allow-Origin"' not in internal_str or '"status_code": 204' not in internal_str:
    print("❌ MISSING in internal host: CORS headers and OPTIONS 204")
    sys.exit(1)

if '"Access-Control-Allow-Methods"' not in internal_str:
    print("❌ MISSING in internal host: Access-Control-Allow-Methods")
    sys.exit(1)

if '"Access-Control-Expose-Headers"' not in internal_str:
    print("❌ MISSING in internal host: Access-Control-Expose-Headers")
    sys.exit(1)

if '"Access-Control-Allow-Headers"' not in internal_str:
    print("❌ MISSING in internal host: Access-Control-Allow-Headers")
    sys.exit(1)

if '"X-Frame-Options"' not in internal_str or '"Referrer-Policy"' not in internal_str or '"Content-Security-Policy"' not in internal_str:
    print("❌ MISSING in internal host: Security headers (X-Frame-Options, Referrer-Policy, Content-Security-Policy)")
    sys.exit(1)

print("✅ Internal Web Host Semantic Validations Passed")


# API
api_routes = find_routes_with_exact_hosts({"api.weltgewebe.net"})
if not api_routes:
    print("❌ MISSING: exact host matches for api.weltgewebe.net")
    sys.exit(1)

print("--- API Host Semantic Validations ---")
api_str = json.dumps(api_routes)
if '"dial": "weltgewebe-api:8080"' not in api_str:
    print("❌ MISSING in api host: API Upstream (weltgewebe-api:8080)")
    sys.exit(1)

if "file_server" in api_str or "/srv/" in api_str:
    print("❌ UNEXPECTED in api host: static file server or root mounts")
    sys.exit(1)
print("✅ API Host Semantic Validations Passed")

print("--- Negative Tests ---")
all_str = json.dumps(data)
negatives = [
    "weltweb.net",
    "www.weltweb.net",
    "weltweberei.org",
    "www.weltweberei.org",
    "heimserver.home.arpa",
]
for neg in negatives:
    if neg in all_str:
        print(f"❌ UNEXPECTED globally: {neg}")
        sys.exit(1)

internal_hosts_to_check = ["leitstand.heimgewebe.home.arpa", "weltgewebe.home.arpa", "api.weltgewebe.home.arpa"]
for internal in internal_hosts_to_check:
    if internal not in all_str:
        print(f"❌ MISSING INTERNAL HOST globally: {internal}")
        sys.exit(1)

print("✅ Negative Tests Passed")
print("== All structural Caddyfile tests passed ==")
