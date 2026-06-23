#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "== Testing sync_caddyfile.sh Logic =="

mkdir -p "$TEST_DIR/opt/heimgewebe/edge"
mkdir -p "$TEST_DIR/repo/edge"

export EDGE_DIR="$TEST_DIR/opt/heimgewebe/edge"
export COMPOSE_FILE="$EDGE_DIR/docker-compose.yml"
export CADDY_SERVICE="edge-caddy"
export LIVE_FILE="$EDGE_DIR/Caddyfile"
export CANDIDATE_FILE="$TEST_DIR/repo/edge/Caddyfile.template"
export LOCK_FILE="$TEST_DIR/lock.lock"
touch "$COMPOSE_FILE"

mkdir -p "$TEST_DIR/bin"
export DOCKER_CALL_LOG="$TEST_DIR/docker.log"
export STATE_FILE="$TEST_DIR/state"

cat << 'MOCKDOCKER' > "$TEST_DIR/bin/docker"
#!/bin/bash
printf '%q ' "$@" >> "$DOCKER_CALL_LOG"
printf '\n' >> "$DOCKER_CALL_LOG"

if [[ "$*" == *"caddy validate"* ]]; then
    if [[ "$*" == *"/etc/caddy/Caddyfile"* ]]; then
        VAL_COUNT=$(cat "$STATE_FILE.val_count" 2>/dev/null || echo "0")
        VAL_COUNT=$((VAL_COUNT + 1))
        echo "$VAL_COUNT" > "$STATE_FILE.val_count"
        
        if [ "$VAL_COUNT" = "1" ] && [ "${FAIL_POST_SYNC_VALIDATION:-0}" = "1" ]; then
            echo "Mock: post-sync validation failed" >&2
            exit 1
        fi
        if [ "$VAL_COUNT" = "2" ] && [ "${FAIL_ROLLBACK_VALIDATION:-0}" = "1" ]; then
            echo "Mock: rollback validation failed" >&2
            exit 1
        fi
    fi
    echo "Mock: validate OK"
    exit 0
fi

if [[ "$*" == *"sha256sum /etc/caddy/Caddyfile"* ]]; then
    HASH_COUNT=$(cat "$STATE_FILE.hash_count" 2>/dev/null || echo "0")
    HASH_COUNT=$((HASH_COUNT + 1))
    echo "$HASH_COUNT" > "$STATE_FILE.hash_count"

    if [ "$HASH_COUNT" = "2" ] && [ "${FAIL_POST_SYNC_CONTAINER_HASH:-0}" = "1" ]; then
        echo "0000000000000000000000000000000000000000000000000000000000000000  /etc/caddy/Caddyfile"
    elif [ "$HASH_COUNT" = "3" ] && [ "${FAIL_ROLLBACK_CONTAINER_HASH:-0}" = "1" ]; then
        echo "1111111111111111111111111111111111111111111111111111111111111111  /etc/caddy/Caddyfile"
    else
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
TRUE_LIVE_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')

run_sync() {
    local expected_hash=$1
    export EXPECTED_LIVE_SHA256="$expected_hash"
    > "$DOCKER_CALL_LOG"
    rm -f "$STATE_FILE.val_count" "$STATE_FILE.hash_count"
    bash scripts/edge/sync_caddyfile.sh
}

echo "--- Fall D: Post-Sync Container-Hash Fehler -> Rollback verifiziert ---"
export FAIL_POST_SYNC_CONTAINER_HASH="1"
set +e
run_sync "$TRUE_LIVE_HASH" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on post-sync container hash mismatch"
    if [ "$(sha256sum "$LIVE_FILE" | awk '{print $1}')" = "$TRUE_LIVE_HASH" ]; then
        echo "✅ Rollback restored original content and verified OK"
    else
        echo "❌ Rollback did not restore original content"
        exit 1
    fi
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
export FAIL_POST_SYNC_CONTAINER_HASH="0"

echo "--- Fall E: Rollback-Validierung schlägt ebenfalls fehl (CRITICAL 255) ---"
export FAIL_POST_SYNC_VALIDATION="1"
export FAIL_ROLLBACK_VALIDATION="1"
set +e
run_sync "$TRUE_LIVE_HASH" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 255 ]; then
    echo "✅ Rollback failed validation and returned critical exit 255"
else
    echo "❌ Expected exit 255, got $EXIT_CODE"
    exit 1
fi
export FAIL_POST_SYNC_VALIDATION="0"
export FAIL_ROLLBACK_VALIDATION="0"

echo "== All runbook script tests passed =="
