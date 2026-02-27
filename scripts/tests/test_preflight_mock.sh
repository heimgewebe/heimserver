#!/usr/bin/env bash
set -euo pipefail

# test_preflight_mock.sh
# Tests the specific logic of the preflight check using mocked `ss`

log() { echo "TEST: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRIPT="./ops/checks/preflight.sh"
MOCK_BIN=$(mktemp -d)
export PATH="$MOCK_BIN:$PATH"

setup_mocks() {
    # Mock everything needed for preflight to run without errors
    cat <<EOF > "$MOCK_BIN/sudo"
#!/bin/bash
"\$@"
EOF
    chmod +x "$MOCK_BIN/sudo"

    cat <<EOF > "$MOCK_BIN/ip"
#!/bin/bash
echo "mock ip"
EOF
    chmod +x "$MOCK_BIN/ip"

    cat <<EOF > "$MOCK_BIN/docker"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/docker"

    cat <<EOF > "$MOCK_BIN/iptables"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/iptables"

    cat <<EOF > "$MOCK_BIN/sysctl"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/sysctl"

    cat <<EOF > "$MOCK_BIN/wg"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/wg"

    cat <<EOF > "$MOCK_BIN/getent"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/getent"

    cat <<EOF > "$MOCK_BIN/curl"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/curl"
}

cleanup() {
    rm -rf "$MOCK_BIN"
}
trap cleanup EXIT

setup_mocks

# TEST 1: Public Exposure (0.0.0.0:8080) -> WARN
log "Running Test 1: Public Exposure (0.0.0.0:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 0.0.0.0:8080 0.0.0.0:* users:((\"my-app\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on 0.0.0.0:8080"
else
    echo "$OUTPUT"
    fail "Test 1 Failed: Did not detect violation"
fi

# TEST 2: Docker Proxy (docker-proxy:8080) -> WARN
log "Running Test 2: Docker Proxy (docker-proxy:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 :::8080 :::* users:((\"docker-proxy\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on docker-proxy"
else
    echo "$OUTPUT"
    fail "Test 2 Failed: Did not detect violation"
fi

# TEST 3: Localhost Only (127.0.0.1:8080) -> ALLOW (OK)
log "Running Test 3: Localhost Only (127.0.0.1:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 127.0.0.1:8080 0.0.0.0:* users:((\"code-server\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "localhost-only (Allowed"; then
    log "PASS: Allows localhost-only"
else
    echo "$OUTPUT"
    fail "Test 3 Failed: Did not allow localhost"
fi

# TEST 4: Wildcard Bind (*:8080) -> WARN
log "Running Test 4: Wildcard Bind (*:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 *:8080 *:* users:((\"rogue-app\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on *:8080"
else
    echo "$OUTPUT"
    fail "Test 4 Failed: Did not detect violation"
fi

echo "ALL PREFLIGHT LOGIC TESTS PASSED."
