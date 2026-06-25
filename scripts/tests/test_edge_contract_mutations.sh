#!/usr/bin/env bash
# test_edge_contract_mutations.sh — Non-destructive structural mutation tests.
# Mutations are applied to temporary copies; tracked files are never modified.
# Exit codes from validate_caddy_contract.py: 0=pass, 1=contract violation, 2=diagnostic failure
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATE="edge/Caddyfile.template"
VALIDATOR="scripts/edge/validate_caddy_contract.py"

if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: Template not found at $TEMPLATE" >&2
    exit 1
fi

# ── Safety: record SHA256 of all tracked files before mutations ───────────────
PRE_SHA="$(find scripts/ edge/ runbooks/ -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}')"

MUTATION_DIR="$(mktemp -d)"
trap 'rm -rf "$MUTATION_DIR"' EXIT

FAILURES=0

# ── Caddyfile mutation runner ─────────────────────────────────────────────────
# Usage: run_caddy_mutant <desc> <mutated_template> <expected_exit> [<expected_stderr_substring>]
run_caddy_mutant() {
    local desc="$1"
    local mutated_file="$2"
    local expected_rc="$3"
    local expected_stderr="${4:-}"

    local actual_rc=0
    local stderr_out
    stderr_out="$(python3 "$VALIDATOR" --caddyfile "$mutated_file" 2>&1 >/dev/null)" || actual_rc=$?

    if [[ "$actual_rc" -ne "$expected_rc" ]]; then
        echo "❌ FAIL [$desc]: expected exit $expected_rc, got $actual_rc"
        echo "   stderr: $stderr_out"
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [[ -n "$expected_stderr" ]] && ! echo "$stderr_out" | grep -qF "$expected_stderr"; then
        echo "❌ FAIL [$desc]: expected stderr to contain ${expected_stderr@Q}, got: $stderr_out"
        FAILURES=$((FAILURES + 1))
        return
    fi

    echo "✅ PASS [$desc] (exit $actual_rc)"
}

# ── Compose mutation runner ───────────────────────────────────────────────────
# Usage: run_compose_mutant <desc> <json_fixture> <expected_exit> [<expected_stderr_substring>]
COMPOSE_VALIDATOR="scripts/edge/validate_compose_contract.py"
run_compose_mutant() {
    local desc="$1"
    local json_fixture="$2"
    local expected_rc="$3"
    local expected_stderr="${4:-}"

    local fixture_file
    fixture_file="$MUTATION_DIR/compose_fixture_$(date +%N).json"
    printf '%s\n' "$json_fixture" > "$fixture_file"

    local actual_rc=0
    local stderr_out
    stderr_out="$(python3 "$COMPOSE_VALIDATOR" --json "$fixture_file" 2>&1 >/dev/null)" || actual_rc=$?

    if [[ "$actual_rc" -ne "$expected_rc" ]]; then
        echo "❌ FAIL [$desc]: expected exit $expected_rc, got $actual_rc"
        echo "   stderr: $stderr_out"
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [[ -n "$expected_stderr" ]] && ! echo "$stderr_out" | grep -qF "$expected_stderr"; then
        echo "❌ FAIL [$desc]: expected stderr to contain ${expected_stderr@Q}, got: $stderr_out"
        FAILURES=$((FAILURES + 1))
        return
    fi

    echo "✅ PASS [$desc] (exit $actual_rc)"
}

echo "== Running Edge Contract Mutations =="
echo ""

# ── Baseline (must pass) ──────────────────────────────────────────────────────
echo "-- Baseline --"
BASELINE="$MUTATION_DIR/Caddyfile.baseline"
cp "$TEMPLATE" "$BASELINE"
run_caddy_mutant "Baseline (unmodified)" "$BASELINE" 0

echo ""
echo "-- Caddyfile Mutations (expect exit 1, CONTRACT VIOLATION in stderr) --"

# Mutant 1: admin off → must be rejected
M1="$MUTATION_DIR/m1.template"
sed 's/admin localhost:2019/admin off/' "$TEMPLATE" > "$M1"
run_caddy_mutant "Mutant 1: admin off" "$M1" 1 "CONTRACT VIOLATION"

# Mutant 2: admin wildcard :2019
M2="$MUTATION_DIR/m2.template"
sed 's/admin localhost:2019/admin :2019/' "$TEMPLATE" > "$M2"
run_caddy_mutant "Mutant 2: admin wildcard (:2019)" "$M2" 1 "CONTRACT VIOLATION"

# Mutant 3: wrong API upstream
M3="$MUTATION_DIR/m3.template"
sed 's/weltgewebe-api:8080/wrong-api:9999/' "$TEMPLATE" > "$M3"
run_caddy_mutant "Mutant 3: wrong API upstream (wrong-api:9999)" "$M3" 1 "CONTRACT VIOLATION"

# Mutant 4: basemap root changed
M4="$MUTATION_DIR/m4.template"
sed 's|/srv/weltgewebe-basemap|/srv/wrong-basemap|g' "$TEMPLATE" > "$M4"
run_caddy_mutant "Mutant 4: basemap root changed (/srv/wrong-basemap)" "$M4" 1 "CONTRACT VIOLATION"

# Mutant 5: no-store removed (version.json cache)
M5="$MUTATION_DIR/m5.template"
sed '/Cache-Control.*no-store/d' "$TEMPLATE" > "$M5"
run_caddy_mutant "Mutant 5: no-store Cache-Control removed" "$M5" 1 "CONTRACT VIOLATION"

# Mutant 6: CSP value changed
M6="$MUTATION_DIR/m6.template"
sed 's/Content-Security-Policy/X-Removed-CSP-Header/' "$TEMPLATE" > "$M6"
run_caddy_mutant "Mutant 6: CSP header removed" "$M6" 1 "CONTRACT VIOLATION"

# Mutant 7: move the actual adapted UI fallback before the basemap route.
# Caddy may canonically reorder Caddyfile directives during adaptation, so this
# ordering counterexample mutates the adapted JSON contract surface itself.
M7_BASE_JSON="$MUTATION_DIR/m7.baseline.json"
M7_JSON="$MUTATION_DIR/m7.fallback-before-basemap.json"

docker run \
   --rm \
   --pull=never \
   --network none \
   -v "$MUTATION_DIR:/candidate:ro" \
   caddy:2.8.4 \
   caddy adapt \
      --adapter caddyfile \
      --config /candidate/Caddyfile.baseline \
   > "$M7_BASE_JSON"

python3 - "$M7_BASE_JSON" "$M7_JSON" << 'PYEOF'
import json
import sys

source_path, target_path = sys.argv[1:3]

with open(source_path, encoding="utf-8") as handle:
    data = json.load(handle)

servers = data.get("apps", {}).get("http", {}).get("servers", {})


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


def contains_web_root(node):
    if isinstance(node, dict):
        if (
            node.get("handler") == "vars"
            and node.get("root") == "/srv/weltgewebe-web"
        ):
            return True
        return any(contains_web_root(value) for value in node.values())
    if isinstance(node, list):
        return any(contains_web_root(value) for value in node)
    return False


candidate_route_sets = []

for server in servers.values():
    for host_route in server.get("routes", []):
        if "weltgewebe.home.arpa" not in route_hosts(host_route):
            continue

        for handler in host_route.get("handle", []):
            if handler.get("handler") != "subroute":
                continue

            sibling_routes = handler.get("routes", [])
            available_paths = {
                path
                for route in sibling_routes
                for path in route_paths(route)
            }

            required_paths = {
                "/api",
                "/_app/version.json",
                "/_app/immutable/*",
                "/local-basemap/*",
                "/api/*",
            }
            if required_paths.issubset(available_paths):
                candidate_route_sets.append(sibling_routes)

if len(candidate_route_sets) != 1:
    raise SystemExit(
        "Mutant 7 setup failed: expected exactly one HTTPS route set, "
        f"found {len(candidate_route_sets)}"
    )

routes = candidate_route_sets[0]

basemap_matches = [
    index
    for index, route in enumerate(routes)
    if "/local-basemap/*" in route_paths(route)
]
fallback_matches = [
    index
    for index, route in enumerate(routes)
    if not route_paths(route) and contains_web_root(route)
]

if len(basemap_matches) != 1:
    raise SystemExit(
        "Mutant 7 setup failed: expected exactly one basemap route, "
        f"found {len(basemap_matches)}"
    )

if len(fallback_matches) != 1:
    raise SystemExit(
        "Mutant 7 setup failed: expected exactly one UI fallback, "
        f"found {len(fallback_matches)}"
    )

basemap_index = basemap_matches[0]
fallback_index = fallback_matches[0]

fallback_route = routes.pop(fallback_index)
if fallback_index < basemap_index:
    basemap_index -= 1

routes.insert(basemap_index, fallback_route)

new_fallback_index = next(
    index
    for index, route in enumerate(routes)
    if not route_paths(route) and contains_web_root(route)
)
new_basemap_index = next(
    index
    for index, route in enumerate(routes)
    if "/local-basemap/*" in route_paths(route)
)

if new_fallback_index >= new_basemap_index:
    raise SystemExit(
        "Mutant 7 setup failed: fallback was not moved before basemap"
    )

with open(target_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYEOF

actual_rc=0
stderr_out="$(
   python3 "$VALIDATOR" --adapted-json "$M7_JSON" 2>&1 >/dev/null
)" || actual_rc=$?

if [[ "$actual_rc" -ne 1 ]]; then
   echo "❌ FAIL [Mutant 7: adapted UI fallback before basemap route]: expected exit 1, got $actual_rc"
   echo "   stderr: $stderr_out"
   FAILURES=$((FAILURES + 1))
elif ! grep -qF "Route ordering violation" <<< "$stderr_out"; then
   echo "❌ FAIL [Mutant 7: adapted UI fallback before basemap route]: missing route-order diagnostic"
   echo "   stderr: $stderr_out"
   FAILURES=$((FAILURES + 1))
else
   echo "✅ PASS [Mutant 7: adapted UI fallback before basemap route] (exit 1)"
fi

echo ""
echo "-- Compose Mutations (JSON fixtures, expect exit 1) --"

# (VALID_COMPOSE_JSON is retained as documentation for the fixture structure above)

# Mutant 8: Port 80 missing
M8_JSON='{
  "services": {
    "caddy": {
      "container_name": "edge-caddy",
      "ports": [
        {"published": 443, "target": 443, "protocol": "tcp"}
      ],
      "volumes": []
    }
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}'
run_compose_mutant "Mutant 8: Port 80 missing" "$M8_JSON" 1 "CONTRACT VIOLATION"

# Mutant 9: Port 443 missing
M9_JSON='{
  "services": {
    "caddy": {
      "container_name": "edge-caddy",
      "ports": [
        {"published": 80, "target": 80, "protocol": "tcp"}
      ],
      "volumes": []
    }
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}'
run_compose_mutant "Mutant 9: Port 443 missing" "$M9_JSON" 1 "CONTRACT VIOLATION"

# Mutant 10: Port 2019 published
M10_JSON='{
  "services": {
    "caddy": {
      "container_name": "edge-caddy",
      "ports": [
        {"published": 80, "target": 80, "protocol": "tcp"},
        {"published": 443, "target": 443, "protocol": "tcp"},
        {"published": 2019, "target": 2019, "protocol": "tcp"}
      ],
      "volumes": []
    }
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}'
run_compose_mutant "Mutant 10: Port 2019 published" "$M10_JSON" 1 "CONTRACT VIOLATION"

# Mutant 11: 443→80 instead of 443→443
M11_JSON='{
  "services": {
    "caddy": {
      "container_name": "edge-caddy",
      "ports": [
        {"published": 80, "target": 80, "protocol": "tcp"},
        {"published": 443, "target": 80, "protocol": "tcp"}
      ],
      "volumes": []
    }
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}'
run_compose_mutant "Mutant 11: 443→80 wrong mapping" "$M11_JSON" 1 "CONTRACT VIOLATION"

# Mutant 12: network_mode: host
M12_JSON='{
  "services": {
    "caddy": {
      "container_name": "edge-caddy",
      "network_mode": "host",
      "ports": [
        {"published": 80, "target": 80, "protocol": "tcp"},
        {"published": 443, "target": 443, "protocol": "tcp"}
      ],
      "volumes": []
    }
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}'
run_compose_mutant "Mutant 12: network_mode: host" "$M12_JSON" 1 "CONTRACT VIOLATION"

echo ""
echo "-- Post-Mutation Working Tree Integrity Check --"
POST_SHA="$(find scripts/ edge/ runbooks/ -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}')"
if [[ "$PRE_SHA" == "$POST_SHA" ]]; then
    echo "✅ Working tree unchanged: all tracked files identical before and after mutations"
else
    echo "❌ FAIL: Working tree SHA changed during mutation tests!"
    echo "   Pre:  $PRE_SHA"
    echo "   Post: $POST_SHA"
    FAILURES=$((FAILURES + 1))
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "== All mutation tests passed (12 mutants) =="
else
    echo "== FAILED: $FAILURES mutation test(s) failed ==" >&2
    exit 1
fi
