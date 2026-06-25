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
JSON_MUTATOR="scripts/tests/edge_contract_json_mutations.py"

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

# ── Adapted-JSON mutation runner ─────────────────────────────────────────────
run_caddy_json_case() {
    local desc="$1"
    local mutation="$2"
    local expected_rc="$3"
    local expected_stderr="${4:-}"
    local mutated_json="$MUTATION_DIR/${mutation}.json"

    python3 "$JSON_MUTATOR" \
        --source "$BASELINE_JSON" \
        --output "$mutated_json" \
        --mutation "$mutation"

    if cmp -s "$BASELINE_JSON" "$mutated_json"; then
        echo "❌ FAIL [$desc]: mutation produced unchanged JSON"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local actual_rc=0
    local stderr_out
    stderr_out="$(
        python3 "$VALIDATOR" --adapted-json "$mutated_json" \
            2>&1 >/dev/null
    )" || actual_rc=$?

    if [[ "$actual_rc" -ne "$expected_rc" ]]; then
        echo "❌ FAIL [$desc]: expected exit $expected_rc, got $actual_rc"
        echo "   stderr: $stderr_out"
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [[ -n "$expected_stderr" ]] \
        && ! grep -qF "$expected_stderr" <<< "$stderr_out"; then
        echo "❌ FAIL [$desc]: expected diagnostic ${expected_stderr@Q}"
        echo "   stderr: $stderr_out"
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

BASELINE_JSON="$MUTATION_DIR/Caddyfile.baseline.json"
docker run \
    --rm \
    --pull=never \
    --network none \
    -v "$MUTATION_DIR:/candidate:ro" \
    caddy:2.8.4 \
    caddy adapt \
        --adapter caddyfile \
        --config /candidate/Caddyfile.baseline \
    > "$BASELINE_JSON"

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

# Positive control: IPv6 loopback must be accepted.
run_caddy_json_case \
    "Positive control: IPv6 loopback admin" \
    "ipv6-admin" \
    0

# Mutant 7: actual adapted fallback precedes basemap.
run_caddy_json_case \
    "Mutant 7: adapted UI fallback before basemap route" \
    "fallback-before-basemap" \
    1 \
    "Route ordering violation"

# Mutants 13-16 keep values globally present but misplace them.
run_caddy_json_case \
    "Mutant 13: version no-store moved to UI fallback" \
    "version-cache-misplaced" \
    1 \
    "version metadata route"

run_caddy_json_case \
    "Mutant 14: PMTiles CORS moved to UI fallback" \
    "cors-misplaced" \
    1 \
    "PMTiles branch"

run_caddy_json_case \
    "Mutant 15: OPTIONS 204 moved outside PMTiles branch" \
    "options-misplaced" \
    1 \
    "OPTIONS matcher and 204 response"

run_caddy_json_case \
    "Mutant 16: PMTiles file_server removed" \
    "pmtiles-file-server-missing" \
    1 \
    "root and file_server must coexist"

echo ""
echo "-- CADDY_IMAGE execution seam --"

MOCK_BIN="$MUTATION_DIR/mock-bin"
MOCK_DOCKER_LOG="$MUTATION_DIR/mock-docker.log"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/docker" <<'MOCKDOCKER'
#!/usr/bin/env bash
printf '%s
' "$*" >> "$MOCK_DOCKER_LOG"

if [[ "$1" == "image" && "$2" == "inspect" ]]; then
    [[ "$3" == "contract-test:caddy" ]] || exit 97
    exit 0
fi

if [[ "$1" == "run" ]]; then
    [[ " $* " == *" contract-test:caddy "* ]] || exit 98
    cat "$MOCK_ADAPTED_JSON"
    exit 0
fi

exit 99
MOCKDOCKER
chmod +x "$MOCK_BIN/docker"

export MOCK_DOCKER_LOG
export MOCK_ADAPTED_JSON="$BASELINE_JSON"

if PATH="$MOCK_BIN:$PATH" \
    CADDY_IMAGE="contract-test:caddy" \
    python3 "$VALIDATOR" --caddyfile "$BASELINE" \
    >/dev/null 2>&1; then
    if grep -qF "image inspect contract-test:caddy" "$MOCK_DOCKER_LOG" \
        && grep -Eq '^run .* contract-test:caddy ' "$MOCK_DOCKER_LOG"; then
        echo "✅ PASS [CADDY_IMAGE inspected and executed consistently]"
    else
        echo "❌ FAIL [CADDY_IMAGE seam]: image mismatch"
        cat "$MOCK_DOCKER_LOG"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "❌ FAIL [CADDY_IMAGE seam]: validator failed"
    cat "$MOCK_DOCKER_LOG"
    FAILURES=$((FAILURES + 1))
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
    echo "== All mutation tests passed (16 mutants + 2 positive controls) =="
else
    echo "== FAILED: $FAILURES contract test(s) failed ==" >&2
    exit 1
fi
