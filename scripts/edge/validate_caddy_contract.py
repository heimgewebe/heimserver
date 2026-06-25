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
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional


# ── Helpers ────────────────────────────────────────────────────────────────────

CADDY_IMAGE = os.environ.get("CADDY_IMAGE", "caddy:2.8.4")


def die(code: int, msg: str) -> None:
    print(f"{'CONTRACT VIOLATION' if code == 1 else 'DIAGNOSTIC FAILURE'}: {msg}", file=sys.stderr)
    sys.exit(code)


def adapt_caddyfile(caddyfile_path: str) -> dict:
    """Run caddy adapt via Docker and return parsed JSON. Exits on failure."""
    candidate = Path(caddyfile_path).resolve()
    candidate_dir = candidate.parent
    candidate_name = candidate.name

    # Check that image exists locally before attempting docker run
    try:
        inspect = subprocess.run(
            ["docker", "image", "inspect", CADDY_IMAGE],
            capture_output=True,
        )
        if inspect.returncode != 0:
            die(2, f"Caddy Docker image not found locally: {CADDY_IMAGE!r}. "
                   f"Pull it first: docker pull {CADDY_IMAGE}")
    except FileNotFoundError:
        die(2, "docker not found")

    try:
        result = subprocess.run(
            [
                "docker", "run", "--rm",
                "--pull=never",
                "--network", "none",
                "-v", f"{candidate_dir}:/candidate:ro",
                "caddy:2.8.4",
                "caddy", "adapt",
                "--adapter", "caddyfile",
                "--config", f"/candidate/{candidate_name}",
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
    """Flatten every route exactly once via direct subroute descent."""
    result = []
    for route in routes:
        result.append(route)
        for handler in route.get("handle", []):
            if handler.get("handler") == "subroute":
                result.extend(walk_routes(handler.get("routes", [])))
    return result

def get_path_matchers(route: dict) -> list:
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


def count_reverse_proxy_upstreams(routes: list) -> int:
    """Count total upstream entries across all reverse_proxy handlers."""
    count = 0
    for rp in find_handler_recursive(routes, "reverse_proxy"):
        count += len(rp.get("upstreams", []))
    return count


def has_file_server_root(routes: list, root: str) -> bool:
    """Check that at least one file_server route uses the given root."""
    # root is set via a "vars" handler type in Caddy JSON
    for h in find_handler_recursive(routes, "vars"):
        if h.get("root") == root:
            return True
    return False


def find_route_by_path_prefix(flat_routes: list, prefix: str) -> Optional[dict]:
    """Find the first route that has a path matcher matching the given prefix."""
    for r in flat_routes:
        paths = get_path_matchers(r)
        if any(p == prefix or p.startswith(prefix) or prefix.rstrip("/*") in p for p in paths):
            return r
    return None


def has_cache_control_exact(routes: list, expected_value: str) -> bool:
    """Verify that routes set the expected exact Cache-Control value somewhere."""
    flat_str = json.dumps(routes)
    return expected_value in flat_str


def has_static_response_status(routes: list, status: int) -> bool:
    for sr in find_handler_recursive(routes, "static_response"):
        if sr.get("status_code") == status:
            return True
    return False


def get_all_matched_hosts(data: dict) -> set:
    """Collect all hostnames referenced in any route's host matcher."""
    hosts = set()
    for r in all_routes(data):
        for m in r.get("match", []):
            hosts.update(m.get("host", []))
    return hosts


def find_route_index_with_any_path(flat: list, path_substrings: list) -> Optional[int]:
    """Find the lowest index of routes matching any of the given path substrings."""
    for i, r in enumerate(flat):
        paths = get_path_matchers(r)
        if any(any(sub in p for sub in path_substrings) for p in paths):
            return i
    return None


def find_route_index_with_root(flat: list, root: str) -> Optional[int]:
    """Find the index of the first route in flat that has a vars handler with the given root."""
    for i, r in enumerate(flat):
        if find_handler_recursive([r], "vars"):
            for h in find_handler_recursive([r], "vars"):
                if h.get("root") == root:
                    return i
    return None


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

    # API upstream must be present
    if not has_reverse_proxy_dial(flat, "weltgewebe-api:8080"):
        die(1, "Public web host: missing reverse_proxy upstream weltgewebe-api:8080")

    # Check basemap root via vars handler
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

    # Cache control — exact string check in JSON
    for expected_cc in [
        "public, max-age=31536000, immutable",
        "no-store",
        "no-cache, must-revalidate",
    ]:
        if not has_cache_control_exact(flat, expected_cc):
            die(1, f"Public web host: missing Cache-Control value: {expected_cc!r}")

    print("✅ Public web host contract OK")


def check_api_host(data: dict) -> None:
    """api.weltgewebe.net must proxy to weltgewebe-api:8080 and have no file server."""
    routes = all_routes(data)
    host_routes = routes_for_host(routes, "api.weltgewebe.net")
    if not host_routes:
        die(1, "No route with exact host api.weltgewebe.net")


    if not has_reverse_proxy_dial(host_routes, "weltgewebe-api:8080"):
        die(1, "API host: missing reverse_proxy upstream weltgewebe-api:8080")

    # Exactly one upstream — no over-specification
    upstream_count = count_reverse_proxy_upstreams(host_routes)
    if upstream_count != 1:
        die(1, f"API host: expected exactly 1 upstream, found {upstream_count}")

    if find_handler_recursive(host_routes, "file_server"):
        die(1, "API host: unexpected file_server handler present")

    host_str = json.dumps(host_routes)
    if "/srv/" in host_str:
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

    # UI web root
    if not has_file_server_root(flat, "/srv/weltgewebe-web"):
        die(1, "Internal host: missing file_server root /srv/weltgewebe-web")

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

    # Cache-Control values — exact match in JSON
    for expected_cc in [
        "public, max-age=31536000, immutable",
        "no-store",
        "no-cache, must-revalidate",
    ]:
        if not has_cache_control_exact(flat, expected_cc):
            die(1, f"Internal host: missing Cache-Control value: {expected_cc!r}")

    # Security headers — exact values, not partial checks
    security_checks = {
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
    }
    for hdr, expected_val in security_checks.items():
        val = get_header_val(flat, hdr)
        if not val:
            die(1, f"Internal host: missing security header {hdr}")
        if val != expected_val:
            die(1, f"Internal host: {hdr} expected exact value {expected_val!r}, got {val!r}")

    # CSP must be present
    csp = get_header_val(flat, "Content-Security-Policy")
    if not csp:
        die(1, "Internal host: missing Content-Security-Policy header")

    print("✅ Internal host contract OK")


def check_route_ordering(data: dict) -> None:
    """Verify direct host-route ordering before the general UI fallback.

    Caddy adapts each site into a host wrapper whose first-level subroute
    contains the ordered sibling routes. Ordering must be checked on those
    siblings. Recursively searching the whole host wrapper misclassifies the
    wrapper itself as the fallback because it contains the fallback below it.
    """
    routes = all_routes(data)
    host_roots = routes_for_host(routes, "weltgewebe.home.arpa")
    if not host_roots:
        return  # already caught by the required-host check

    required_paths = {
        "API redirect": "/api",
        "version metadata": "/_app/version.json",
        "immutable assets": "/_app/immutable/*",
        "local basemap": "/local-basemap/*",
        "API proxy": "/api/*",
    }

    candidates = []
    for host_root in host_roots:
        sibling_routes = []
        for handler in host_root.get("handle", []):
            if handler.get("handler") == "subroute":
                sibling_routes.extend(handler.get("routes", []))

        available_paths = {
            path
            for route in sibling_routes
            for path in get_path_matchers(route)
        }
        if set(required_paths.values()).issubset(available_paths):
            candidates.append(sibling_routes)

    if len(candidates) != 1:
        die(
            1,
            "Route ordering: expected exactly one HTTPS host route set with "
            f"all required paths, found {len(candidates)}",
        )

    sibling_routes = candidates[0]

    def unique_path_index(label: str, expected_path: str) -> int:
        matches = [
            index
            for index, route in enumerate(sibling_routes)
            if expected_path in get_path_matchers(route)
        ]
        if len(matches) != 1:
            die(
                1,
                f"Route ordering: {label} expected exactly once at "
                f"{expected_path!r}, found {len(matches)}",
            )
        return matches[0]

    fallback_matches = []
    for index, route in enumerate(sibling_routes):
        if get_path_matchers(route):
            continue

        has_web_root = any(
            handler.get("root") == "/srv/weltgewebe-web"
            for handler in find_handler_recursive([route], "vars")
        )
        if has_web_root:
            fallback_matches.append(index)

    if len(fallback_matches) != 1:
        die(
            1,
            "Route ordering: expected exactly one unmatched UI fallback with "
            f"root /srv/weltgewebe-web, found {len(fallback_matches)}",
        )

    fallback_index = fallback_matches[0]

    route_indices = {
        label: unique_path_index(label, expected_path)
        for label, expected_path in required_paths.items()
    }

    for label, route_index in route_indices.items():
        if route_index >= fallback_index:
            die(
                1,
                f"Route ordering violation: {label} route ({route_index}) "
                f"appears at or after UI fallback ({fallback_index})",
            )

    ordered = ", ".join(
        f"{label}={route_indices[label]}"
        for label in required_paths
    )
    print(
        "✅ Route ordering: direct routes precede UI fallback "
        f"({ordered}, fallback={fallback_index})"
    )


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
        print(f"Adapting {args.caddyfile} with {CADDY_IMAGE} ...")
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
