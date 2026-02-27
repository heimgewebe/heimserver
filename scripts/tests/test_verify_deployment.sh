#!/usr/bin/env bash
set -euo pipefail

# test_verify_deployment.sh
# Tests hermetic health check logic of weltgewebe-up (Internal Only Policy)

log() { echo "TEST: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRIPT="./scripts/weltgewebe-up"

# Mock Environment Setup
setup_mocks() {
    # Create temp bin directory for mocks
    MOCK_BIN=$(mktemp -d)
    export PATH="$MOCK_BIN:$PATH"

    # Mock curl: always succeed for valid URL, fail otherwise
    cat <<EOF > "$MOCK_BIN/curl"
#!/bin/bash
if [[ "\$1" == "-fsS" ]]; then
    # Simple mock: if URL contains "example.com", succeed
    if [[ "\$2" == *"example.com"* ]]; then exit 0; fi
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/curl"

    # Mock docker: behave differently based on args
    cat <<EOF > "$MOCK_BIN/docker"
#!/bin/bash
if [[ "\$1" == "inspect" ]]; then
    if [[ "\$*" == *"Health.Status"* ]]; then
        # Default behavior: unknown or starting
        if [[ -f "/tmp/mock_docker_health_healthy" ]]; then echo "healthy"; exit 0; fi
        if [[ -f "/tmp/mock_docker_health_unhealthy" ]]; then echo "unhealthy"; exit 0; fi
        if [[ -f "/tmp/mock_docker_health_running" ]]; then echo ""; exit 0; fi # No Healthcheck
        echo "starting"
    elif [[ "\$*" == *"State.Status"* ]]; then
        echo "running"
    else
        echo "{}"
    fi
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/docker"
}

cleanup() {
    rm -rf "$MOCK_BIN"
    rm -f /tmp/mock_*
}
trap cleanup EXIT

setup_mocks

# TEST 1: Internal API (Docker Health = healthy)
log "Running Test 1: Internal API (Docker Health = healthy)..."
touch /tmp/mock_docker_health_healthy
# Should succeed quickly due to "healthy" status
if timeout 5s bash "$SCRIPT" >/dev/null; then
    log "PASS: Test 1 (Internal API, Healthy Container)"
else
    fail "Test 1 Failed"
fi
rm /tmp/mock_docker_health_healthy

# TEST 2: Internal API (No Healthcheck, just Running)
# Should WARN but succeed
log "Running Test 2: Internal API (Running, No Healthcheck)..."
touch /tmp/mock_docker_health_running
if timeout 5s bash "$SCRIPT" >/dev/null; then
    log "PASS: Test 2 (Running Container Fallback)"
else
    fail "Test 2 Failed"
fi
rm /tmp/mock_docker_health_running

# TEST 3: Unhealthy Container (Should Fail)
log "Running Test 3: Unhealthy Container..."
touch /tmp/mock_docker_health_unhealthy
# We expect failure here, so we wrap it
if ! timeout 5s bash "$SCRIPT" >/dev/null 2>&1; then
    log "PASS: Test 3 (Correctly Failed on Unhealthy)"
else
    fail "Test 3 Failed (Should have failed but succeeded)"
fi
rm /tmp/mock_docker_health_unhealthy

echo "ALL TESTS PASSED."
