#!/usr/bin/env bash
set -euo pipefail

# test_preflight_mock.sh
# Tests the specific logic of the preflight check using mocked `ss`

log() { echo "TEST: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRIPT="./ops/checks/preflight.sh"
export ALLOW_HISTORICAL_HOST_READ=1
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
# Format: Netid State Recv-Q Send-Q Local_Address:Port Peer_Address:Port Process
echo "LISTEN 0 0 0.0.0.0:8080 0.0.0.0:* users:((\"my-app\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on 0.0.0.0:8080"
else
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 1 Failed: Did not detect violation"
fi

# TEST 2: Docker Proxy (docker-proxy:8080) -> WARN
log "Running Test 2: Docker Proxy (docker-proxy:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
# Note: Peer is :::* which could confuse a full-line match, but docker-proxy ensures VIOLATION anyway
echo "LISTEN 0 0 :::8080 :::* users:((\"docker-proxy\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on docker-proxy"
else
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 2 Failed: Did not detect violation"
fi

# TEST 3: Localhost Only (127.0.0.1:8080) -> ALLOW (OK)
# CRITICAL: Peer address is 0.0.0.0:*, which MUST NOT trigger a public bind violation.
log "Running Test 3: Localhost Only (127.0.0.1:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 127.0.0.1:8080 0.0.0.0:* users:((\"code-server\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 3 Failed: False Positive! Reported VIOLATION on localhost with peer 0.0.0.0:*."
elif echo "$OUTPUT" | grep -q "localhost-only (Allowed"; then
    log "PASS: Allows localhost-only (ignores peer column)"
else
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 3 Failed: Did not explicitly allow localhost"
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
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 4 Failed: Did not detect violation"
fi

# TEST 5: IPv6 Public Exposure (:::8080) -> WARN
log "Running Test 5: IPv6 Public Exposure (:::8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 :::8080 :::* users:((\"my-app\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION on :::8080"
else
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 5 Failed: Did not detect violation"
fi

# TEST 6: Mixed (Localhost + Public) -> WARN
log "Running Test 6: Mixed (Localhost + Public)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 127.0.0.1:8080 0.0.0.0:* users:((\"good-app\",pid=123,fd=4))"
echo "LISTEN 0 0 0.0.0.0:8080 0.0.0.0:* users:((\"bad-app\",pid=456,fd=5))"
EOF
chmod +x "$MOCK_BIN/ss"

OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    log "PASS: Detects VIOLATION in mixed output"
else
    echo "OUTPUT WAS:"
    echo "$OUTPUT"
    fail "Test 6 Failed: Did not detect violation in mixed output"
fi

# TEST 7: LAN bind -> VIOLATION
log "Running Test 7: LAN bind (192.168.178.10:5432)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 192.168.178.10:5432 0.0.0.0:* users:((\"postgres\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"
OUTPUT=$(bash "$SCRIPT" 2>&1)
echo "$OUTPUT" | grep -q "VIOLATION" || fail "Test 7 Failed: Did not reject LAN bind"
log "PASS: Detects VIOLATION on LAN bind"

# TEST 8: IPv6 loopback -> ALLOW
log "Running Test 8: IPv6 loopback ([::1]:8080)..."
cat <<EOF > "$MOCK_BIN/ss"
#!/bin/bash
echo "LISTEN 0 0 [::1]:8080 [::]:* users:((\"local-app\",pid=123,fd=4))"
EOF
chmod +x "$MOCK_BIN/ss"
OUTPUT=$(bash "$SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "VIOLATION"; then
    fail "Test 8 Failed: False positive on IPv6 loopback"
fi
echo "$OUTPUT" | grep -q "localhost-only (Allowed" || fail "Test 8 Failed: Did not allow IPv6 loopback"
log "PASS: Allows IPv6 loopback"

echo "ALL PREFLIGHT LOGIC TESTS PASSED."
