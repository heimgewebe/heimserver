#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TEMPLATE="edge/Caddyfile.template"
TEST_SCRIPT="scripts/tests/test_caddy_template.py"

if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: Template not found at $TEMPLATE" >&2
    exit 1
fi

TEMP_TEMPLATE="$(mktemp)"
trap 'rm -f "$TEMP_TEMPLATE"' EXIT

# Helper to run python script with injected TEMPLATE path
run_test() {
    local desc="$1"
    local expect_fail="$2"
    
    echo "Testing: $desc"
    # test_caddy_template.py hardcodes TEMPLATE="edge/Caddyfile.template". We can overwrite it temporarily
    # but that's bad for concurrency. It's better to just backup and restore.
    
    local old_hash="$(sha256sum "$TEMPLATE" | awk '{print $1}')"
    cp "$TEMP_TEMPLATE" "$TEMPLATE"
    
    set +e
    python3 "$TEST_SCRIPT" >/dev/null 2>&1
    local code=$?
    set -e
    
    # Restore original immediately
    git checkout "$TEMPLATE"
    
    if [[ "$expect_fail" == "1" ]]; then
        if [[ $code -eq 0 ]]; then
            echo "❌ FAIL: Expected test to fail, but it passed for $desc"
            exit 1
        else
            echo "  ✅ PASS: Test correctly rejected $desc"
        fi
    else
        if [[ $code -ne 0 ]]; then
            echo "❌ FAIL: Expected test to pass, but it failed for $desc"
            exit 1
        else
            echo "  ✅ PASS: Test accepted $desc"
        fi
    fi
}

echo "== Running Edge Contract Mutations =="

# Baseline
cp "$TEMPLATE" "$TEMP_TEMPLATE"
run_test "Baseline (unmodified)" 0

# Mutation 1: admin off
sed -e 's/admin localhost:2019/admin off/' "$TEMPLATE" > "$TEMP_TEMPLATE"
run_test "admin off" 1

# Mutation 2: admin exposed
sed -e 's/admin localhost:2019/admin :2019/' "$TEMPLATE" > "$TEMP_TEMPLATE"
run_test "admin exposed (:2019)" 1

# Mutation 3: Missing CORS for internal
sed -e '/header Access-Control-Allow-Origin/d' "$TEMPLATE" > "$TEMP_TEMPLATE"
run_test "Missing CORS header" 1

# Mutation 4: Missing Cache-Control
sed -e '/header Cache-Control "no-store"/d' "$TEMPLATE" > "$TEMP_TEMPLATE"
run_test "Missing no-store Cache-Control" 1

# Mutation 5: Wrong API Upstream
sed -e 's/weltgewebe-api:8080/weltgewebe-api:8081/' "$TEMPLATE" > "$TEMP_TEMPLATE"
run_test "Wrong API Upstream" 1

echo "== All mutation tests passed =="
