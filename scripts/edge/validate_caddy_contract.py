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


def positive_int_env(name: str, default: int) -> int:
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except ValueError:
        die(2, f"{name} must be a positive integer, got {raw!r}")
    if value <= 0:
        die(2, f"{name} must be a positive integer, got {raw!r}")
    return value


SUBPROCESS_TIMEOUT_SECONDS = positive_int_env(
    "EDGE_SUBPROCESS_TIMEOUT_SECONDS",
    30,
)


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
            timeout=SUBPROCESS_TIMEOUT_SECONDS,
        )
        if inspect.returncode != 0:
            die(2, f"Caddy Docker image not found locally: {CADDY_IMAGE!r}. "
                   f"Pull it first: docker pull {CADDY_IMAGE}")
    except FileNotFoundError:
        die(2, "docker not found")
    except subprocess.TimeoutExpired:
        die(2, "docker image inspect timed out")

    try:
        result = subprocess.run(
            [
                "docker", "run", "--rm",
                "--pull=never",
                "--network", "none",
                "-v", f"{candidate_dir}:/candidate:ro",
                CADDY_IMAGE,
                "caddy", "adapt",
                "--adapter", "caddyfile",
                "--config", f"/candidate/{candidate_name}",
            ],
            capture_output=True,
            text=True,
            timeout=SUBPROCESS_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        die(2, "docker not found")
    except subprocess.TimeoutExpired:
        die(2, "caddy adapt timed out")

    if result.returncode != 0:
        die(2, f"caddy adapt failed (rc={result.returncode}): {result.stderr.strip()}")

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        die(2, f"caddy adapt output is not valid JSON: {e}")
    if not isinstance(data, dict):
        die(2, "caddy adapt JSON root must be an object")
    return data


def load_json_file(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        die(2, f"Cannot load JSON from {path}: {e}")
    if not isinstance(data, dict):
        die(2, "Adapted Caddy JSON root must be an object")
    return data


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


def walk_routes(routes: list) -> list:
    'Flatten every route exactly once via direct subroute descent.'
    result = []
    for route in routes:
        result.append(route)
        for handler in route.get("handle", []):
            if handler.get("handler") == "subroute":
                result.extend(walk_routes(handler.get("routes", [])))
    return result


def get_path_matchers(route: dict) -> list:
    'Extract direct path matcher values from one route.'
    paths = []
    for matcher in route.get("match", []):
        paths.extend(matcher.get("path", []))
    return paths


def get_path_regexp_patterns(route: dict) -> list:
    'Extract direct path_regexp patterns from one route.'
    patterns = []
    for matcher in route.get("match", []):
        regexp = matcher.get("path_regexp")
        if isinstance(regexp, dict) and regexp.get("pattern"):
            patterns.append(regexp["pattern"])
    return patterns


def direct_subroute_routes(route: dict) -> list:
    'Return direct child routes of subroute handlers on one route.'
    result = []
    for handler in route.get("handle", []):
        if handler.get("handler") == "subroute":
            result.extend(handler.get("routes", []))
    return result


def iter_route_nodes(route: dict):
    'Yield one route and all route descendants exactly once.'
    yield route
    for child in direct_subroute_routes(route):
        yield from iter_route_nodes(child)


def get_header_val(routes: list, header_name: str) -> Optional[str]:
    'Find the first response-header value across a deliberately scoped tree.'
    for handler in find_handler_recursive(routes, "headers"):
        response = handler.get("response", {})
        for key, values in response.get("set", {}).items():
            if key.lower() == header_name.lower() and values:
                return values[0] if isinstance(values, list) else values
    return None


def route_header_values(route: dict, header_name: str) -> list:
    'Return all values for one response header inside one route subtree.'
    values = []
    for handler in find_handler_recursive([route], "headers"):
        response = handler.get("response", {})
        for key, raw_values in response.get("set", {}).items():
            if key.lower() != header_name.lower():
                continue
            if isinstance(raw_values, list):
                values.extend(str(value) for value in raw_values)
            else:
                values.append(str(raw_values))
    return values


def route_has_header_exact(route: dict, header_name: str, expected: str) -> bool:
    """Require exactly one value, rejecting duplicates and contradictions."""
    return route_header_values(route, header_name) == [expected]


def route_has_handler(route: dict, handler_type: str) -> bool:
    return bool(find_handler_recursive([route], handler_type))


def route_has_root(route: dict, root: str) -> bool:
    return any(
        handler.get("root") == root
        for handler in find_handler_recursive([route], "vars")
    )


def route_has_static_response_status(route: dict, status: int) -> bool:
    return any(
        handler.get("status_code") == status
        for handler in find_handler_recursive([route], "static_response")
    )


def direct_static_response_handlers(route: dict) -> list:
    return [
        handler
        for handler in route.get("handle", [])
        if handler.get("handler") == "static_response"
    ]


def route_has_method_static_response(
    route: dict,
    method: str,
    status: int,
) -> bool:
    'Require method matcher and static response on the same nested route.'
    for node in iter_route_nodes(route):
        methods = []
        for matcher in node.get("match", []):
            methods.extend(matcher.get("method", []))
        if method not in methods:
            continue
        if any(
            handler.get("handler") == "static_response"
            and handler.get("status_code") == status
            for handler in node.get("handle", [])
        ):
            return True
    return False


def has_reverse_proxy_dial(routes: list, dial: str) -> bool:
    'Check a deliberately scoped route tree for one proxy destination.'
    for proxy in find_handler_recursive(routes, "reverse_proxy"):
        for upstream in proxy.get("upstreams", []):
            if upstream.get("dial") == dial:
                return True
    return False


def count_reverse_proxy_upstreams(routes: list) -> int:
    'Count upstream entries inside a deliberately scoped route tree.'
    return sum(
        len(proxy.get("upstreams", []))
        for proxy in find_handler_recursive(routes, "reverse_proxy")
    )


def identity_index(routes: list, target: dict) -> int:
    'Return the index of the exact route object, not an equal dictionary.'
    for index, candidate in enumerate(routes):
        if candidate is target:
            return index
    die(2, "internal validator error: route object is not present")


def get_all_matched_hosts(data: dict) -> set:
    'Collect all hostnames referenced in top-level host matchers.'
    hosts = set()
    for route in all_routes(data):
        for matcher in route.get("match", []):
            hosts.update(matcher.get("host", []))
    return hosts


def unique_host_sibling_routes(
    data: dict,
    hosts: set,
    required_paths: set,
    label: str,
) -> list:
    'Resolve the one HTTPS host route set containing all required paths.'
    candidates = []
    for host_root in routes_for_hosts(all_routes(data), hosts):
        siblings = direct_subroute_routes(host_root)
        available_paths = {
            path
            for route in siblings
            for path in get_path_matchers(route)
        }
        if required_paths.issubset(available_paths):
            candidates.append(siblings)

    if len(candidates) != 1:
        die(
            1,
            f"{label}: expected exactly one route set containing "
            f"{sorted(required_paths)}, found {len(candidates)}",
        )
    return candidates[0]


def unique_direct_route_by_path(
    routes: list,
    expected_path: str,
    label: str,
) -> dict:
    matches = [
        route
        for route in routes
        if expected_path in get_path_matchers(route)
    ]
    if len(matches) != 1:
        die(
            1,
            f"{label}: expected exactly one direct route for "
            f"{expected_path!r}, found {len(matches)}",
        )
    return matches[0]


def unique_nested_route_by_regexp(
    route: dict,
    pattern_fragment: str,
    label: str,
) -> dict:
    matches = [
        node
        for node in iter_route_nodes(route)
        if any(
            pattern_fragment in pattern
            for pattern in get_path_regexp_patterns(node)
        )
    ]
    if len(matches) != 1:
        die(
            1,
            f"{label}: expected exactly one nested path_regexp containing "
            f"{pattern_fragment!r}, found {len(matches)}",
        )
    return matches[0]


def unique_fallback_route(routes: list, root: str, label: str) -> dict:
    matches = [
        route
        for route in routes
        if not get_path_matchers(route)
        and not get_path_regexp_patterns(route)
        and route_has_root(route, root)
        and route_has_handler(route, "file_server")
    ]
    if len(matches) != 1:
        die(
            1,
            f"{label}: expected exactly one unmatched file-server fallback "
            f"for {root!r}, found {len(matches)}",
        )
    return matches[0]


def check_static_web_route_contract(routes: list, label: str) -> None:
    'Validate route-bound static UI and basemap semantics.'
    version_route = unique_direct_route_by_path(
        routes,
        "/_app/version.json",
        f"{label} version metadata",
    )
    immutable_route = unique_direct_route_by_path(
        routes,
        "/_app/immutable/*",
        f"{label} immutable assets",
    )
    basemap_route = unique_direct_route_by_path(
        routes,
        "/local-basemap/*",
        f"{label} basemap",
    )
    fallback_route = unique_fallback_route(
        routes,
        "/srv/weltgewebe-web",
        f"{label} UI fallback",
    )

    if not (
        route_has_root(version_route, "/srv/weltgewebe-web")
        and route_has_handler(version_route, "file_server")
        and route_has_header_exact(
            version_route,
            "Cache-Control",
            "no-store",
        )
    ):
        die(
            1,
            f"{label} version metadata route: expected web root, "
            "file_server and exact Cache-Control 'no-store'",
        )

    if not (
        route_has_root(immutable_route, "/srv/weltgewebe-web")
        and route_has_handler(immutable_route, "file_server")
        and route_has_header_exact(
            immutable_route,
            "Cache-Control",
            "public, max-age=31536000, immutable",
        )
    ):
        die(
            1,
            f"{label} immutable route: expected web root, file_server "
            "and exact immutable Cache-Control",
        )

    if not route_has_header_exact(
        fallback_route,
        "Cache-Control",
        "no-cache, must-revalidate",
    ):
        die(
            1,
            f"{label} UI fallback: missing exact no-cache Cache-Control",
        )

    pmtiles_route = unique_nested_route_by_regexp(
        basemap_route,
        r"\.pmtiles$",
        f"{label} PMTiles branch",
    )
    metadata_route = unique_nested_route_by_regexp(
        basemap_route,
        r"\.meta\.json$",
        f"{label} metadata branch",
    )

    map_style_matches = [
        route
        for route in direct_subroute_routes(basemap_route)
        if not get_path_matchers(route)
        and not get_path_regexp_patterns(route)
        and route_has_root(route, "/srv/weltgewebe-map-style")
        and route_has_handler(route, "file_server")
    ]
    if len(map_style_matches) != 1:
        die(
            1,
            f"{label} map-style branch: expected exactly one unmatched "
            f"file-server branch, found {len(map_style_matches)}",
        )

    if not (
        route_has_root(pmtiles_route, "/srv/weltgewebe-basemap")
        and route_has_handler(pmtiles_route, "file_server")
    ):
        die(
            1,
            f"{label} PMTiles branch: root and file_server must coexist "
            "inside the PMTiles route subtree",
        )

    if not (
        route_has_root(metadata_route, "/srv/weltgewebe-basemap")
        and route_has_handler(metadata_route, "file_server")
    ):
        die(
            1,
            f"{label} metadata branch: root and file_server must coexist "
            "inside the metadata route subtree",
        )

    required_cors = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
        "Access-Control-Expose-Headers": (
            "Content-Range, Accept-Ranges, Content-Length"
        ),
        "Access-Control-Allow-Headers": "Range, If-None-Match",
    }
    for header_name, expected_value in required_cors.items():
        if not route_has_header_exact(
            pmtiles_route,
            header_name,
            expected_value,
        ):
            die(
                1,
                f"{label} PMTiles branch: missing exact "
                f"{header_name}={expected_value!r}",
            )

    if not route_has_method_static_response(
        pmtiles_route,
        "OPTIONS",
        204,
    ):
        die(
            1,
            f"{label} PMTiles branch: OPTIONS matcher and 204 response "
            "must occur on the same nested route",
        )


# ── Contract assertions ────────────────────────────────────────────────────────

def check_admin(data: dict) -> None:
    'Admin must exist and use one explicitly allowed loopback address.'
    admin = data.get("admin")
    if admin is None:
        die(1, "Admin configuration is missing entirely")

    if admin.get("disabled", False):
        die(
            1,
            "Admin is disabled (admin off) — required for "
            "reload/rollback workflow",
        )

    listen = admin.get("listen", "")
    if listen != "127.0.0.1:2019":
        die(
            1,
            "Admin listen address must be exactly "
            f"'127.0.0.1:2019', got {listen!r}",
        )

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
    'Validate public web routing on direct route siblings.'
    required_paths = {
        "/_app/version.json",
        "/_app/immutable/*",
        "/local-basemap/*",
        "/health/*",
        "/api/*",
    }
    routes = unique_host_sibling_routes(
        data,
        {"weltgewebe.net", "www.weltgewebe.net"},
        required_paths,
        "Public web host",
    )

    api_route = unique_direct_route_by_path(
        routes,
        "/api/*",
        "Public web API",
    )
    health_route = unique_direct_route_by_path(
        routes,
        "/health/*",
        "Public web health",
    )

    for route_label, route in [
        ("Public web API", api_route),
        ("Public web health", health_route),
    ]:
        if not has_reverse_proxy_dial(
            [route],
            "weltgewebe-api:8080",
        ):
            die(
                1,
                f"{route_label}: missing reverse_proxy upstream "
                "weltgewebe-api:8080",
            )
        if count_reverse_proxy_upstreams([route]) != 1:
            die(1, f"{route_label}: expected exactly one upstream")
        if route_has_handler(route, "file_server"):
            die(1, f"{route_label}: unexpected file_server")

    check_static_web_route_contract(routes, "Public web host")
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
    'Validate internal web routing on direct route siblings.'
    required_paths = {
        "/api",
        "/_app/version.json",
        "/_app/immutable/*",
        "/local-basemap/*",
        "/api/*",
    }
    routes = unique_host_sibling_routes(
        data,
        {"weltgewebe.home.arpa"},
        required_paths,
        "Internal host",
    )

    redirect_route = unique_direct_route_by_path(
        routes,
        "/api",
        "Internal API redirect",
    )
    redirect_handlers = direct_static_response_handlers(redirect_route)
    if len(redirect_handlers) != 1:
        die(
            1,
            "Internal API redirect: expected exactly one direct "
            f"static_response handler, found {len(redirect_handlers)}",
        )
    redirect_handler = redirect_handlers[0]
    if redirect_handler.get("status_code") != 308:
        die(
            1,
            "Internal API redirect: expected status 308, got "
            f"{redirect_handler.get('status_code')!r}",
        )
    headers = redirect_handler.get("headers", {})
    if not isinstance(headers, dict):
        die(1, "Internal API redirect: missing headers map")
    locations = [
        value
        for key, value in headers.items()
        if key.lower() == "location"
    ]
    if len(locations) != 1:
        die(
            1,
            "Internal API redirect: expected exactly one Location header, "
            f"found {len(locations)}",
        )
    location = locations[0]
    normalized_location = location if isinstance(location, list) else [location]
    if normalized_location != ["/api/"]:
        die(
            1,
            "Internal API redirect: expected Location '/api/', got "
            f"{normalized_location!r}",
        )

    api_route = unique_direct_route_by_path(
        routes,
        "/api/*",
        "Internal API proxy",
    )
    if not has_reverse_proxy_dial(
        [api_route],
        "weltgewebe-api:8080",
    ):
        die(
            1,
            "Internal API proxy: missing upstream weltgewebe-api:8080",
        )
    if count_reverse_proxy_upstreams([api_route]) != 1:
        die(1, "Internal API proxy: expected exactly one upstream")
    if route_has_handler(api_route, "file_server"):
        die(1, "Internal API proxy: unexpected file_server")

    check_static_web_route_contract(routes, "Internal host")

    host_roots = routes_for_host(
        all_routes(data),
        "weltgewebe.home.arpa",
    )
    security_checks = {
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
    }
    for header_name, expected_value in security_checks.items():
        actual = get_header_val(host_roots, header_name)
        if actual != expected_value:
            die(
                1,
                f"Internal host: {header_name} expected "
                f"{expected_value!r}, got {actual!r}",
            )
    print("✅ Internal host contract OK")


def check_route_ordering_for_hosts(
    data: dict,
    hosts: set,
    labels: dict,
    label: str,
) -> None:
    'Verify all specific routes for one host set precede the UI fallback.'
    required_paths = set(labels.values())
    routes = unique_host_sibling_routes(
        data,
        hosts,
        required_paths,
        f"Route ordering {label}",
    )
    fallback_route = unique_fallback_route(
        routes,
        "/srv/weltgewebe-web",
        f"Route ordering {label}",
    )
    fallback_index = identity_index(routes, fallback_route)

    indices = {}
    for route_label, expected_path in labels.items():
        route = unique_direct_route_by_path(
            routes,
            expected_path,
            f"Route ordering {label} {route_label}",
        )
        route_index = identity_index(routes, route)
        indices[route_label] = route_index
        if route_index >= fallback_index:
            die(
                1,
                f"Route ordering violation: {label} {route_label} route "
                f"({route_index}) appears at or after UI fallback "
                f"({fallback_index})",
            )

    ordered = ", ".join(
        f"{route_label}={indices[route_label]}"
        for route_label in labels
    )
    print(
        f"✅ Route ordering {label}: direct routes precede UI fallback "
        f"({ordered}, fallback={fallback_index})"
    )


def check_route_ordering(data: dict) -> None:
    check_route_ordering_for_hosts(
        data,
        {"weltgewebe.home.arpa"},
        {
            "API redirect": "/api",
            "version metadata": "/_app/version.json",
            "immutable assets": "/_app/immutable/*",
            "local basemap": "/local-basemap/*",
            "API proxy": "/api/*",
        },
        "internal host",
    )
    check_route_ordering_for_hosts(
        data,
        {"weltgewebe.net", "www.weltgewebe.net"},
        {
            "version metadata": "/_app/version.json",
            "immutable assets": "/_app/immutable/*",
            "local basemap": "/local-basemap/*",
            "API proxy": "/api/*",
            "health": "/health/*",
        },
        "public web host",
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
