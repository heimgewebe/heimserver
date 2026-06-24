#!/usr/bin/env python3
"""
validate_caddy_contract.py — Structural Caddy contract validator.

Usage:
    python3 scripts/edge/validate_caddy_contract.py --caddyfile edge/Caddyfile.template
    python3 scripts/edge/validate_caddy_contract.py --adapted-json /path/to/adapted.json

Exit codes:
    0 — all contracts pass
    1 — contract violation (wrong config)
    2 — diagnosis not possible (tooling failure)
"""
import argparse
import json
import subprocess
import sys
from typing import Any, Optional


# ── Helpers ────────────────────────────────────────────────────────────────────

def die(code: int, msg: str) -> None:
    print(f"{'CONTRACT VIOLATION' if code == 1 else 'DIAGNOSTIC FAILURE'}: {msg}", file=sys.stderr)
    sys.exit(code)


def adapt_caddyfile(caddyfile_path: str) -> dict:
    """Run caddy adapt via Docker and return parsed JSON. Exits on failure."""
    try:
        result = subprocess.run(
            [
                "docker", "run", "--rm",
                "--pull=never",
                "--network", "none",
                "-v", f"{subprocess.getoutput('pwd')}:/repo:ro",
                "-w", "/repo",
                "caddy:2.8.4",
                "caddy", "adapt",
                "--adapter", "caddyfile",
                "--config", caddyfile_path,
            ],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        die(2, "docker not found")

    if result.returncode != 0:
        die(2, f"caddy adapt failed (rc={result.returncode}): {result.stderr.strip()}")

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        die(2, f"caddy adapt output is not valid JSON: {e}")


def load_json_file(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        die(2, f"Cannot load JSON from {path}: {e}")


# ── Structural helpers ─────────────────────────────────────────────────────────

def all_routes(data: dict) -> list:
    """Collect all routes from all HTTP servers."""
    routes = []
    servers = data.get("apps", {}).get("http", {}).get("servers", {})
    for srv in servers.values():
        routes.extend(srv.get("routes", []))
    return routes


def routes_for_host(routes: list, host: str) -> list:
    """Return routes whose match.host list equals exactly {host}."""
    result = []
    for r in routes:
        for m in r.get("match", []):
            if set(m.get("host", [])) == {host}:
                result.append(r)
    return result


def routes_for_hosts(routes: list, hosts: set) -> list:
    """Return routes whose match.host set equals exactly hosts."""
    result = []
    for r in routes:
        for m in r.get("match", []):
            if set(m.get("host", [])) == hosts:
                result.append(r)
    return result


def find_handler_recursive(node: Any, handler_type: str) -> list:
    """Recursively find all handlers of a given type in nested route/subroute structures."""
    found = []
    if isinstance(node, dict):
        if node.get("handler") == handler_type:
            found.append(node)
        for v in node.values():
            found.extend(find_handler_recursive(v, handler_type))
    elif isinstance(node, list):
        for item in node:
            found.extend(find_handler_recursive(item, handler_type))
    return found


def find_subroutes(routes: list) -> list:
    """Collect all subroute handlers (nested routes)."""
    return find_handler_recursive(routes, "subroute")


def walk_routes(routes: list) -> list:
    """Flatten all routes including those inside subroutes."""
    result = list(routes)
    for sr in find_subroutes(routes):
        result.extend(walk_routes(sr.get("routes", [])))
    return result


def get_path_matchers(route: dict) -> list[str]:
    """Extract all path matcher values from a route."""
    paths = []
    for m in route.get("match", []):
        paths.extend(m.get("path", []))
    return paths


def get_handlers(route: dict, handler_type: str) -> list:
    """Get direct handlers of a specific type in a route."""
    return [h for h in route.get("handle", []) if h.get("handler") == handler_type]


def get_header_val(routes: list, header_name: str) -> Optional[str]:
    """Find the set value of a response header across all handler trees."""
    for h in find_handler_recursive(routes, "headers"):
        response = h.get("response", {})
        for key, val_list in response.get("set", {}).items():
            if key.lower() == header_name.lower() and val_list:
                return val_list[0] if isinstance(val_list, list) else val_list
    return None


def has_reverse_proxy_dial(routes: list, dial: str) -> bool:
    """Check that at least one reverse_proxy handler dials the given address."""
    for rp in find_handler_recursive(routes, "reverse_proxy"):
        upstreams = rp.get("upstreams", [])
        for u in upstreams:
            if u.get("dial") == dial:
                return True
    return False


def has_file_server_root(routes: list, root: str) -> bool:
    """Check that at least one file_server route uses the given root."""
    for sr in find_handler_recursive(routes, "static_response"):
        pass  # not relevant
    for h in find_handler_recursive(routes, "file_server"):
        # root is typically set via vars/vars_root handler or root directive
        pass
    # root is set via a "vars" or "root" handler type in Caddy JSON
    for h in find_handler_recursive(routes, "vars"):
        if h.get("root") == root:
            return True
    return False


def has_cache_control(routes: list, path_prefix: str, expected_value: str) -> bool:
    """Verify that routes matching a path prefix set the expected Cache-Control value."""
    flat = walk_routes(routes)
    for r in flat:
        paths = get_path_matchers(r)
        if not any(p.startswith(path_prefix) or path_prefix.startswith(p.rstrip("*")) for p in paths):
            continue
        for h in find_handler_recursive(r.get("handle", []), "headers"):
            sets = h.get("response", {}).get("set", {})
            cc = sets.get("Cache-Control", sets.get("cache-control", []))
            if isinstance(cc, list):
                if any(expected_value in v for v in cc):
                    return True
            elif expected_value in cc:
                return True
    return False


def has_static_response_status(routes: list, status: int) -> bool:
    for sr in find_handler_recursive(routes, "static_response"):
        if sr.get("status_code") == status:
            return True
    return False


def get_all_matched_hosts(data: dict) -> set[str]:
    """Collect all hostnames referenced in any route's host matcher."""
    hosts = set()
    for r in all_routes(data):
        for m in r.get("match", []):
            hosts.update(m.get("host", []))
    return hosts


# ── Contract assertions ────────────────────────────────────────────────────────

def check_admin(data: dict) -> None:
    """Admin must be present, not disabled, and bound to loopback only."""
    admin = data.get("admin")
    if admin is None:
        die(1, "Admin configuration is missing entirely")

    if admin.get("disabled", False):
        die(1, "Admin is disabled (admin off) — required for reload/rollback workflow")

    listen = admin.get("listen", "")
    if not listen:
        die(1, f"Admin listen address is empty — expected loopback binding")

    # Reject wildcard / non-loopback
    bad_patterns = ["0.0.0.0", "::", "*:", "0.0.0.0:"]
    for bad in bad_patterns:
        if bad in listen:
            die(1, f"Admin is bound to non-loopback address: {listen}")

    # Must contain loopback
    good_patterns = ["127.0.0.1", "localhost", "[::1]"]
    if not any(g in listen for g in good_patterns):
        die(1, f"Admin listen address is not a loopback address: {listen}")

    print(f"✅ Admin bound to loopback: {listen}")


def check_no_forbidden_hosts(data: dict) -> None:
    """Ensure forbidden hostnames do not appear in any host matcher."""
    forbidden = {
        "weltweb.net",
        "www.weltweb.net",
        "weltweberei.org",
        "www.weltweberei.org",
        "heimserver.home.arpa",
    }
    found = get_all_matched_hosts(data)
    bad = found & forbidden
    if bad:
        die(1, f"Forbidden hosts found in route matchers: {sorted(bad)}")
    print(f"✅ No forbidden hosts")


def check_required_internal_hosts(data: dict) -> None:
    """Ensure required internal host entries are present in matchers."""
    required = {
        "leitstand.heimgewebe.home.arpa",
        "weltgewebe.home.arpa",
        "api.weltgewebe.home.arpa",
    }
    found = get_all_matched_hosts(data)
    missing = required - found
    if missing:
        die(1, f"Required internal hosts missing from route matchers: {sorted(missing)}")
    print(f"✅ Required internal hosts present")


def check_public_web_host(data: dict) -> None:
    """Check public web hosts: weltgewebe.net + www.weltgewebe.net."""
    routes = all_routes(data)
    host_routes = routes_for_hosts(routes, {"weltgewebe.net", "www.weltgewebe.net"})
    if not host_routes:
        die(1, "No route with exact hosts {weltgewebe.net, www.weltgewebe.net}")

    flat = walk_routes(host_routes)

    if not has_reverse_proxy_dial(flat, "weltgewebe-api:8080"):
        die(1, "Public web host: missing reverse_proxy upstream weltgewebe-api:8080")

    # Check basemap root
    if not has_file_server_root(flat, "/srv/weltgewebe-basemap"):
        die(1, "Public web host: missing file_server root /srv/weltgewebe-basemap")

    # Check map style root
    if not has_file_server_root(flat, "/srv/weltgewebe-map-style"):
        die(1, "Public web host: missing file_server root /srv/weltgewebe-map-style")

    # CORS
    if not has_static_response_status(flat, 204):
        die(1, "Public web host: missing OPTIONS 204 static response")

    cors_origin = get_header_val(flat, "Access-Control-Allow-Origin")
    if not cors_origin:
        die(1, "Public web host: missing Access-Control-Allow-Origin header")

    # Cache control
    flat_str = json.dumps(flat)
    for expected_cc in [
        "public, max-age=31536000, immutable",
        "no-store",
        "no-cache, must-revalidate",
    ]:
        if expected_cc not in flat_str:
            die(1, f"Public web host: missing Cache-Control value: {expected_cc!r}")

    print("✅ Public web host contract OK")


def check_api_host(data: dict) -> None:
    """api.weltgewebe.net must proxy to weltgewebe-api:8080 and have no file server."""
    routes = all_routes(data)
    host_routes = routes_for_host(routes, "api.weltgewebe.net")
    if not host_routes:
        die(1, "No route with exact host api.weltgewebe.net")

    flat = walk_routes(host_routes)

    if not has_reverse_proxy_dial(flat, "weltgewebe-api:8080"):
        die(1, "API host: missing reverse_proxy upstream weltgewebe-api:8080")

    if find_handler_recursive(flat, "file_server"):
        die(1, "API host: unexpected file_server handler present")

    flat_str = json.dumps(flat)
    if "/srv/" in flat_str:
        die(1, "API host: unexpected /srv/ root path reference")

    print("✅ API host contract OK")


def check_internal_host(data: dict) -> None:
    """weltgewebe.home.arpa — full structural contract."""
    routes = all_routes(data)
    host_routes = routes_for_host(routes, "weltgewebe.home.arpa")
    if not host_routes:
        die(1, "No route with exact host weltgewebe.home.arpa")

    flat = walk_routes(host_routes)
    flat_str = json.dumps(flat)

    # API upstream
    if not has_reverse_proxy_dial(flat, "weltgewebe-api:8080"):
        die(1, "Internal host: missing reverse_proxy upstream weltgewebe-api:8080")

    # Basemap roots
    if not has_file_server_root(flat, "/srv/weltgewebe-basemap"):
        die(1, "Internal host: missing file_server root /srv/weltgewebe-basemap")

    if not has_file_server_root(flat, "/srv/weltgewebe-map-style"):
        die(1, "Internal host: missing file_server root /srv/weltgewebe-map-style")

    # CORS
    cors_origin = get_header_val(flat, "Access-Control-Allow-Origin")
    if not cors_origin:
        die(1, "Internal host: missing Access-Control-Allow-Origin header")

    for cors_header in ["Access-Control-Allow-Methods", "Access-Control-Allow-Headers",
                        "Access-Control-Expose-Headers"]:
        if cors_header not in flat_str:
            die(1, f"Internal host: missing header {cors_header}")

    # OPTIONS 204
    if not has_static_response_status(flat, 204):
        die(1, "Internal host: missing OPTIONS 204 static response")

    # Cache-Control values
    for expected_cc in [
        "public, max-age=31536000, immutable",
        "no-store",
        "no-cache, must-revalidate",
    ]:
        if expected_cc not in flat_str:
            die(1, f"Internal host: missing Cache-Control value: {expected_cc!r}")

    # Security headers — exact values
    security_checks = {
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
    }
    for hdr, expected_val in security_checks.items():
        val = get_header_val(flat, hdr)
        if not val:
            die(1, f"Internal host: missing security header {hdr}")
        if expected_val not in val:
            die(1, f"Internal host: {hdr} expected to contain {expected_val!r}, got {val!r}")

    # CSP must be present (full value check)
    csp = get_header_val(flat, "Content-Security-Policy")
    if not csp:
        die(1, "Internal host: missing Content-Security-Policy header")

    # Web root for static UI
    if not has_file_server_root(flat, "/srv/weltgewebe-web"):
        die(1, "Internal host: missing file_server root /srv/weltgewebe-web")

    print("✅ Internal host contract OK")


def check_route_ordering(data: dict) -> None:
    """
    Verify that specific basemap/API/asset routes appear before the general UI fallback.
    We do this by finding the index of the first specific-path route and the UI fallback
    in the flat route list for weltgewebe.home.arpa.
    """
    routes = all_routes(data)
    host_routes = routes_for_host(routes, "weltgewebe.home.arpa")
    if not host_routes:
        return  # already caught above

    flat = walk_routes(host_routes)

    specific_paths = ["/local-basemap/", "/api/", "/_app/immutable/"]
    fallback_indicators = ["/index.html", "/_app/version.json"]  # SPA fallback

    first_specific = None
    last_fallback = None

    for i, r in enumerate(flat):
        paths = get_path_matchers(r)
        if any(any(sp in p for sp in specific_paths) for p in paths):
            if first_specific is None:
                first_specific = i

    for i, r in enumerate(flat):
        rstr = json.dumps(r)
        if any(fb in rstr for fb in fallback_indicators):
            last_fallback = i

    if first_specific is not None and last_fallback is not None:
        if first_specific >= last_fallback:
            die(1, f"Route ordering violation: specific route ({first_specific}) "
                f"appears after fallback ({last_fallback})")

    print("✅ Route ordering: specific routes before UI fallback")


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Structural Caddy contract validator")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--caddyfile", metavar="PATH", help="Caddyfile to adapt and validate")
    group.add_argument("--adapted-json", metavar="PATH", help="Pre-adapted JSON file (no Docker needed)")
    args = parser.parse_args()

    if args.adapted_json:
        data = load_json_file(args.adapted_json)
    else:
        print(f"Adapting {args.caddyfile} with Caddy 2.8.4 ...")
        data = adapt_caddyfile(args.caddyfile)

    print("Running contract assertions ...")
    check_admin(data)
    check_no_forbidden_hosts(data)
    check_required_internal_hosts(data)
    check_public_web_host(data)
    check_api_host(data)
    check_internal_host(data)
    check_route_ordering(data)

    print("✅ All Caddy contract checks passed")


if __name__ == "__main__":
    main()
