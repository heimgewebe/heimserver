#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "== Testing sync_caddyfile.sh Logic =="

mkdir -p "$TEST_DIR/opt/heimgewebe/edge"
mkdir -p "$TEST_DIR/repo/edge"

export EDGE_DIR="$TEST_DIR/opt/heimgewebe/edge"
export COMPOSE_FILE="$EDGE_DIR/docker-compose.yml"
unset CADDY_SERVICE
EXPECTED_CADDY_SERVICE="caddy"
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

if [[ "$*" == *"caddy adapt"* ]]; then
    # Produce minimal valid Caddy JSON for contract validator when called from sync
    echo '{"apps":{"http":{"servers":{}}}}'
    exit 0
fi

if [[ "$*" == *"sha256sum /etc/caddy/Caddyfile"* ]]; then
    HASH_COUNT=$(cat "$STATE_FILE.hash_count" 2>/dev/null || echo "0")
    HASH_COUNT=$((HASH_COUNT + 1))
    echo "$HASH_COUNT" > "$STATE_FILE.hash_count"

    if [ "$HASH_COUNT" = "1" ] && [ "${FAIL_PRE_SYNC_CONTAINER_HASH:-0}" = "1" ]; then
        echo "0000000000000000000000000000000000000000000000000000000000000000  /etc/caddy/Caddyfile"
    elif [ "$HASH_COUNT" = "2" ] && [ "${FAIL_POST_SYNC_CONTAINER_HASH:-0}" = "1" ]; then
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

export ADMIN_BOUNDARY_CHECK="$TEST_DIR/mock_guard.sh"
cat << 'MOCKGUARD' > "$ADMIN_BOUNDARY_CHECK"
#!/bin/bash
GUARD_COUNT=$(cat "$STATE_FILE.guard_count" 2>/dev/null || echo "0")
GUARD_COUNT=$((GUARD_COUNT + 1))
echo "$GUARD_COUNT" > "$STATE_FILE.guard_count"

if ls "$LIVE_FILE.bak."* >/dev/null 2>&1; then
    echo "ERROR: Guard called after backup" >&2
    exit 99
fi
if [[ "$(cat "$LIVE_FILE")" != "old_live_content" ]]; then
    echo "ERROR: Guard called after write" >&2
    exit 99
fi

if [[ "${FAIL_GUARD:-0}" != "0" ]]; then
    exit "${FAIL_GUARD}"
fi
exit 0
MOCKGUARD
chmod +x "$ADMIN_BOUNDARY_CHECK"

# Mock contract validator — structural checks are covered by test_caddy_template.py
export CADDY_CONTRACT_VALIDATOR="$TEST_DIR/mock_contract.py"
cat << 'MOCKCONTRACT' > "$CADDY_CONTRACT_VALIDATOR"
#!/usr/bin/env python3
import sys
if "--caddyfile" in sys.argv:
    # Just exit 0 to pass; real checks are done by test_caddy_template.py
    sys.exit(0)
sys.exit(0)
MOCKCONTRACT
chmod +x "$CADDY_CONTRACT_VALIDATOR"

run_sync() {
    local expected_hash=$1
    export EXPECTED_LIVE_SHA256="$expected_hash"
    true > "$DOCKER_CALL_LOG"
    rm -f "$STATE_FILE.val_count" "$STATE_FILE.hash_count" "$STATE_FILE.guard_count"
    rm -f "$LIVE_FILE.bak."*
    if [ "${FAIL_ROLLBACK_VALIDATION:-0}" = "1" ]; then
        bash -x scripts/edge/sync_caddyfile.sh
    else
        bash scripts/edge/sync_caddyfile.sh
    fi
}

echo "--- Setup basic files ---"
echo "old_live_content" > "$LIVE_FILE"
ORIGINAL_INODE=$(stat -c '%i' "$LIVE_FILE")
echo "new_candidate_content" > "$CANDIDATE_FILE"
TRUE_LIVE_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')
ORIGINAL_INODE=$(stat -c '%i' "$LIVE_FILE")

echo "--- Fall 1: fehlende Live-Datei ---"
rm -f "$LIVE_FILE"
set +e
run_sync "anything" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on missing live file"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
echo "old_live_content" > "$LIVE_FILE"
ORIGINAL_INODE=$(stat -c '%i' "$LIVE_FILE")

echo "--- Fall 2: unerwartete Live-Drift ---"
set +e
run_sync "wronghash" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on wrong expected hash"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi

echo "--- Fall 3: No-op bei identischen Hashes ---"
cp "$LIVE_FILE" "$CANDIDATE_FILE"
set +e
run_sync "$TRUE_LIVE_HASH"
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Exited 0 for identical hashes"
else
    echo "❌ Expected exit 0, got $EXIT_CODE"
    exit 1
fi
echo "new_candidate_content" > "$CANDIDATE_FILE"

echo "--- Fall 4: Pre-Sync Host-Container Divergenz ---"
export FAIL_PRE_SYNC_CONTAINER_HASH="1"
set +e
run_sync "$TRUE_LIVE_HASH"
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on pre-sync container drift"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
export FAIL_PRE_SYNC_CONTAINER_HASH="0"

echo "--- Fall 5: Lock-Konkurrenz ---"
exec 8>"$LOCK_FILE"
flock -n 8
set +e
run_sync "$TRUE_LIVE_HASH"
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on lock contention"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
flock -u 8
exec 8>&-

echo "--- Fall 6: Post-Sync Container-Hash Fehler -> Rollback verifiziert ---"
export FAIL_POST_SYNC_CONTAINER_HASH="1"
set +e
run_sync "$TRUE_LIVE_HASH"
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

echo "--- Fall 7: Rollback-Validierung schlägt fehl (CRITICAL 255) ---"
export FAIL_POST_SYNC_VALIDATION="1"
export FAIL_ROLLBACK_VALIDATION="1"
set +e
run_sync "$TRUE_LIVE_HASH"
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

echo "--- Fall 8: erfolgreicher Sync & Inode Erhaltung ---"
if run_sync "$TRUE_LIVE_HASH" >/dev/null; then
    echo "✅ Sync succeeded"
else
    echo "❌ Failed: Sync should succeed"
    exit 1
fi

if ! grep -Fq -- "compose --project-directory $EDGE_DIR -f $COMPOSE_FILE exec -T $EXPECTED_CADDY_SERVICE" "$DOCKER_CALL_LOG"; then
    echo "❌ Docker compose arguments were incorrect!"
    cat "$DOCKER_CALL_LOG"
    exit 1
else
    echo "✅ Docker compose arguments verified"
fi

NEW_INODE=$(stat -c '%i' "$LIVE_FILE")
if [ "$ORIGINAL_INODE" != "$NEW_INODE" ]; then
    echo "❌ Failed: Inode changed during sync!"
    exit 1
else
    echo "✅ Inode preserved"
fi

echo "== All runbook script tests passed =="

echo "--- Fall 9: Guard-Fehler 1 blockiert Mutation ---"
echo "old_live_content" > "$LIVE_FILE"
echo "new_candidate_content" > "$CANDIDATE_FILE"
export FAIL_GUARD="1"
set +e
run_sync "$TRUE_LIVE_HASH" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on guard exit 1"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
if ls "$LIVE_FILE.bak."* >/dev/null 2>&1; then
    echo "❌ Failed: Backup was created despite guard failure"
    exit 1
fi
if [ "$(cat "$STATE_FILE.guard_count" 2>/dev/null)" != "1" ]; then
    echo "❌ Failed: Guard was not called exactly once (count was $(cat "$STATE_FILE.guard_count" 2>/dev/null))"
    exit 1
fi
export FAIL_GUARD="0"

echo "--- Fall 10: Guard-Fehler 2 blockiert Mutation ---"
export FAIL_GUARD="2"
set +e
run_sync "$TRUE_LIVE_HASH" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ $EXIT_CODE -eq 1 ]; then
    echo "✅ Aborted correctly on guard exit 2"
else
    echo "❌ Expected exit 1, got $EXIT_CODE"
    exit 1
fi
export FAIL_GUARD="0"

echo "--- Fall 11: Guard-Aufruf bei No-op ---"
cp "$LIVE_FILE" "$CANDIDATE_FILE"
run_sync "$TRUE_LIVE_HASH" >/dev/null
if [ -f "$STATE_FILE.guard_count" ]; then
    echo "❌ Failed: Guard was called on No-op sync!"
    exit 1
else
    echo "✅ Guard skipped on No-op sync"
fi
echo "new_candidate_content" > "$CANDIDATE_FILE"

echo "== All runbook script tests passed =="
