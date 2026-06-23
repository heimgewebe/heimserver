#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "== Testing sync_caddyfile.sh Logic =="

# Setup mock environment
mkdir -p "$TEST_DIR/opt/heimgewebe/edge"
mkdir -p "$TEST_DIR/repo/edge"

export LIVE_FILE="$TEST_DIR/opt/heimgewebe/edge/Caddyfile"
export CANDIDATE_FILE="$TEST_DIR/repo/edge/Caddyfile.template"

# Create a mock docker command
mkdir -p "$TEST_DIR/bin"
cat << 'MOCKDOCKER' > "$TEST_DIR/bin/docker"
#!/bin/bash
# Mock docker behaviour
if [[ "$*" == *"caddy validate"* ]]; then
    if [[ "$*" == *"/etc/caddy/Caddyfile"* ]]; then
        if [ "$FAIL_CONTAINER_VALIDATION" = "1" ]; then
            echo "Mock: container validation failed" >&2
            exit 1
        fi
    fi
    echo "Mock: validate OK"
    exit 0
fi

if [[ "$*" == *"sha256sum /etc/caddy/Caddyfile"* ]]; then
    if [ "$FAIL_CONTAINER_HASH" = "1" ]; then
        echo "0000000000000000000000000000000000000000000000000000000000000000  /etc/caddy/Caddyfile"
    else
        # Mocking container hash to match host file
        sha256sum "$LIVE_FILE"
    fi
    exit 0
fi
echo "Mock: Unhandled docker command: $*" >&2
exit 1
MOCKDOCKER
chmod +x "$TEST_DIR/bin/docker"
export PATH="$TEST_DIR/bin:$PATH"

echo "old_live_content" > "$LIVE_FILE"
echo "new_candidate_content" > "$CANDIDATE_FILE"
ORIGINAL_INODE=$(stat -c '%i' "$LIVE_FILE")
TRUE_LIVE_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')

run_sync() {
    local expected_hash=$1
    export EXPECTED_LIVE_SHA256="$expected_hash"
    bash scripts/edge/sync_caddyfile.sh
}

export FAIL_CONTAINER_VALIDATION="0"
export FAIL_CONTAINER_HASH="0"

echo "--- Fall A: unerwartete Live-Drift ---"
if run_sync "wronghash" 2>/dev/null; then
    echo "❌ Failed: Should abort on wrong expected hash"
    exit 1
else
    echo "✅ Aborted correctly"
fi

echo "--- Fall D: falscher Container-Hash (Rollback Check) ---"
export FAIL_CONTAINER_HASH="1"
if run_sync "$TRUE_LIVE_HASH" 2>/dev/null; then
    echo "❌ Failed: Should abort and rollback on container hash mismatch"
    exit 1
else
    echo "✅ Aborted correctly on container hash mismatch"
    # Check if rollback occurred
    CURRENT_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')
    if [ "$CURRENT_HASH" = "$TRUE_LIVE_HASH" ]; then
        echo "✅ Rollback restored original content"
    else
        echo "❌ Rollback failed"
        exit 1
    fi
fi
export FAIL_CONTAINER_HASH="0"

echo "--- Fall E: falsche Containervalidierung (Rollback Check) ---"
export FAIL_CONTAINER_VALIDATION="1"
if run_sync "$TRUE_LIVE_HASH" 2>/dev/null; then
    echo "❌ Failed: Should abort and rollback on validation failure"
    exit 1
else
    echo "✅ Aborted correctly on validation failure"
    # Check if rollback occurred
    CURRENT_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')
    if [ "$CURRENT_HASH" = "$TRUE_LIVE_HASH" ]; then
        echo "✅ Rollback restored original content"
    else
        echo "❌ Rollback failed"
        exit 1
    fi
fi
export FAIL_CONTAINER_VALIDATION="0"

echo "--- Fall B: echte beabsichtigte Aktualisierung ---"
if run_sync "$TRUE_LIVE_HASH" >/dev/null; then
    echo "✅ Sync succeeded"
else
    echo "❌ Failed: Sync should succeed"
    exit 1
fi

NEW_INODE=$(stat -c '%i' "$LIVE_FILE")
if [ "$ORIGINAL_INODE" != "$NEW_INODE" ]; then
    echo "❌ Failed: Inode changed during sync!"
    exit 1
else
    echo "✅ Inode preserved"
fi

echo "== All runbook script tests passed =="
