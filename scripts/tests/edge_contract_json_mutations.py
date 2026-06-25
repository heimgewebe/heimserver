#!/usr/bin/env python3
# Deterministic adapted-JSON counterexamples for the Caddy validator.

import argparse
import json
from pathlib import Path

REQUIRED_INTERNAL_PATHS = {
    "/api",
    "/_app/version.json",
    "/_app/immutable/*",
    "/local-basemap/*",
    "/api/*",
}


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


def route_regexps(route):
    patterns = []
    for matcher in route.get("match", []):
        regexp = matcher.get("path_regexp")
        if isinstance(regexp, dict) and regexp.get("pattern"):
            patterns.append(regexp["pattern"])
    return patterns


def direct_children(route):
    children = []
    for handler in route.get("handle", []):
        if handler.get("handler") == "subroute":
            children.extend(handler.get("routes", []))
    return children


def iter_routes(route):
    yield route
    for child in direct_children(route):
        yield from iter_routes(child)


def contains_root(route, expected_root):
    for node in iter_routes(route):
        for handler in node.get("handle", []):
            if (
                handler.get("handler") == "vars"
                and handler.get("root") == expected_root
            ):
                return True
    return False


def contains_handler(route, expected_handler):
    return any(
        handler.get("handler") == expected_handler
        for node in iter_routes(route)
        for handler in node.get("handle", [])
    )


def internal_siblings(data):
    # Return the actual mutable handler["routes"] list from the JSON tree.
    candidates = []
    servers = data.get("apps", {}).get("http", {}).get("servers", {})
    for server in servers.values():
        for host_route in server.get("routes", []):
            if route_hosts(host_route) != {"weltgewebe.home.arpa"}:
                continue

            for handler in host_route.get("handle", []):
                if handler.get("handler") != "subroute":
                    continue

                siblings = handler.get("routes", [])
                available = {
                    path
                    for route in siblings
                    for path in route_paths(route)
                }
                if REQUIRED_INTERNAL_PATHS.issubset(available):
                    candidates.append(siblings)

    if len(candidates) != 1:
        raise SystemExit(
            "expected exactly one internal HTTPS route set, "
            f"found {len(candidates)}"
        )
    return candidates[0]


def identity_index(routes, target):
    # Return the index of the exact object, never an equal dictionary.
    for index, route in enumerate(routes):
        if route is target:
            return index
    raise SystemExit("target route object is not present in route list")


def direct_route(routes, expected_path):
    matches = [
        route for route in routes if expected_path in route_paths(route)
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"expected one route for {expected_path!r}, "
            f"found {len(matches)}"
        )
    return matches[0]


def regexp_route(route, fragment):
    matches = [
        node
        for node in iter_routes(route)
        if any(fragment in pattern for pattern in route_regexps(node))
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"expected one regexp route containing {fragment!r}, "
            f"found {len(matches)}"
        )
    return matches[0]


def fallback_route(routes):
    matches = [
        route
        for route in routes
        if not route_paths(route)
        and not route_regexps(route)
        and contains_root(route, "/srv/weltgewebe-web")
        and contains_handler(route, "file_server")
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"expected one UI fallback, found {len(matches)}"
        )
    return matches[0]


def remove_header(route, header_name):
    removed = []
    for node in iter_routes(route):
        for handler in node.get("handle", []):
            if handler.get("handler") != "headers":
                continue
            response_set = handler.get("response", {}).get("set", {})
            for key in list(response_set):
                if key.lower() == header_name.lower():
                    removed.append((key, response_set.pop(key)))
    if not removed:
        raise SystemExit(f"header not found: {header_name}")
    return removed


def append_headers_to_web_fallback(route, values):
    target = None
    for node in iter_routes(route):
        if contains_root(node, "/srv/weltgewebe-web"):
            target = node
            break
    if target is None:
        raise SystemExit("web fallback target route not found")
    target.setdefault("handle", []).append(
        {
            "handler": "headers",
            "response": {"set": values},
        }
    )


def find_method_route_parent(route, method):
    for node in iter_routes(route):
        for handler in node.get("handle", []):
            if handler.get("handler") != "subroute":
                continue
            child_routes = handler.get("routes", [])
            for index, child in enumerate(child_routes):
                methods = []
                for matcher in child.get("match", []):
                    methods.extend(matcher.get("method", []))
                if method in methods:
                    return child_routes, index
    raise SystemExit(f"method route not found: {method}")


def first_subroute_list(route):
    for handler in route.get("handle", []):
        if handler.get("handler") == "subroute":
            return handler.setdefault("routes", [])
    raise SystemExit("target route has no subroute handler")


def mutate(data, mutation):
    routes = internal_siblings(data)
    basemap = direct_route(routes, "/local-basemap/*")
    fallback = fallback_route(routes)
    version = direct_route(routes, "/_app/version.json")
    pmtiles = regexp_route(basemap, r"\.pmtiles$")

    if mutation == "ipv6-admin":
        data.setdefault("admin", {})["listen"] = "[::1]:2019"
        return

    if mutation == "fallback-before-basemap":
        fallback_index = identity_index(routes, fallback)
        basemap_index = identity_index(routes, basemap)

        moved = routes.pop(fallback_index)
        if fallback_index < basemap_index:
            basemap_index -= 1
        routes.insert(basemap_index, moved)

        new_fallback_index = identity_index(routes, fallback)
        new_basemap_index = identity_index(routes, basemap)
        if new_fallback_index >= new_basemap_index:
            raise SystemExit(
                "fallback-before-basemap mutation did not alter "
                "the actual JSON route list"
            )
        return

    if mutation == "version-cache-misplaced":
        removed = remove_header(version, "Cache-Control")
        values = {key: raw_values for key, raw_values in removed}
        append_headers_to_web_fallback(fallback, values)
        return

    if mutation == "cors-misplaced":
        names = [
            "Access-Control-Allow-Origin",
            "Access-Control-Allow-Methods",
            "Access-Control-Expose-Headers",
            "Access-Control-Allow-Headers",
        ]
        values = {}
        for name in names:
            for key, raw_values in remove_header(pmtiles, name):
                values[key] = raw_values
        append_headers_to_web_fallback(fallback, values)
        return

    if mutation == "options-misplaced":
        parent, index = find_method_route_parent(pmtiles, "OPTIONS")
        moved = parent.pop(index)
        first_subroute_list(fallback).append(moved)
        return

    if mutation == "pmtiles-file-server-missing":
        removed = 0
        for node in iter_routes(pmtiles):
            handlers = node.get("handle", [])
            kept = []
            for handler in handlers:
                if handler.get("handler") == "file_server":
                    removed += 1
                else:
                    kept.append(handler)
            node["handle"] = kept
        if removed == 0:
            raise SystemExit("PMTiles file_server not found")
        return

    raise SystemExit(f"unknown mutation: {mutation}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--mutation",
        required=True,
        choices=[
            "ipv6-admin",
            "fallback-before-basemap",
            "version-cache-misplaced",
            "cors-misplaced",
            "options-misplaced",
            "pmtiles-file-server-missing",
        ],
    )
    args = parser.parse_args()

    source = Path(args.source)
    output = Path(args.output)
    data = json.loads(source.read_text(encoding="utf-8"))
    mutate(data, args.mutation)
    output.write_text(
        json.dumps(data, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
