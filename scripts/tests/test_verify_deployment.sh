#!/usr/bin/env bash
set -euo pipefail

# test_verify_deployment.sh
# Tests hermetic health check logic of weltgewebe-up

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
    # Simple mock: if URL contains "9081", succeed
    if [[ "\$2" == *"9081"* ]]; then exit 0; fi
    # If URL contains "8080", fail unless explicitly set
    if [[ "\$2" == *"8080"* ]]; then exit 1; fi
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
        echo "starting"
    elif [[ "\$*" == *"State.Status"* ]]; then
        echo "running"
    else
        echo "{}"
    fi
elif [[ "\$1" == "compose" ]] && [[ "\$2" == "port" ]]; then
    # Mock compose port output
    if [[ -f "/tmp/mock_compose_port_8080" ]]; then echo "0.0.0.0:8080"; exit 0; fi
    if [[ -f "/tmp/mock_compose_port_unpublished" ]]; then echo ""; exit 0; fi
    echo ""
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/docker"

    # Mock ss: simulate port listeners
    cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
if [[ "\$*" == *"-lntup"* ]]; then
    if [[ -f "/tmp/mock_ss_9081" ]]; then echo "LISTEN 0 0 127.0.0.1:9081"; exit 0; fi
    echo ""
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/ss"
}

cleanup() {
    rm -rf "$MOCK_BIN"
    rm -f /tmp/mock_*
}
trap cleanup EXIT

setup_mocks

# TEST 1: Unpublished API (Docker Health = healthy)
log "Running Test 1: Unpublished API (Docker Health = healthy)..."
touch /tmp/mock_docker_health_healthy
touch /tmp/mock_compose_port_unpublished
# Should succeed quickly due to "healthy" status
if timeout 5s bash "$SCRIPT" >/dev/null; then
    log "PASS: Test 1 (Unpublished API, Healthy Container)"
else
    fail "Test 1 Failed"
fi
rm /tmp/mock_docker_health_healthy

# TEST 2: Published API (Port 8080, Health Check via Port)
# Note: Our script prioritizes Docker Health. If Docker Health is not explicitly healthy,
# it falls back to port check. But our mock curl fails 8080 by default.
# Let's test the PATH where Docker Health is "unknown" but Port is published.
# Wait, script logic: if health != healthy, checks port.
# If port published, tries curl.
log "Running Test 2: Published API (Port 8080)..."
touch /tmp/mock_compose_port_8080
# Mock curl needs to succeed for 8080 here
cat <<EOF > "$MOCK_BIN/curl"
#!/bin/bash
if [[ "\$2" == *"8080"* ]]; then exit 0; fi
exit 1
EOF
chmod +x "$MOCK_BIN/curl"

if timeout 5s bash "$SCRIPT" >/dev/null; then
    log "PASS: Test 2 (Published API, Port Check)"
else
    fail "Test 2 Failed"
fi
rm /tmp/mock_compose_port_8080

# TEST 3: Gateway Check (Port 9081 Active)
log "Running Test 3: Gateway Check (9081)..."
touch /tmp/mock_ss_9081
# Mock curl for 9081
cat <<EOF > "$MOCK_BIN/curl"
#!/bin/bash
if [[ "\$2" == *"9081"* ]]; then exit 0; fi
exit 1
EOF
chmod +x "$MOCK_BIN/curl"

# Ensure API is not healthy/published so it falls through to Gateway check
rm -f /tmp/mock_docker_health_healthy
touch /tmp/mock_compose_port_unpublished

if timeout 5s bash "$SCRIPT" >/dev/null; then
    log "PASS: Test 3 (Gateway Check)"
else
    fail "Test 3 Failed"
fi

echo "ALL TESTS PASSED."
