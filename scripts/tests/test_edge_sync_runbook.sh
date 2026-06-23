#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "== Testing Runbook Logic =="

# Setup mock environment
mkdir -p "$TEST_DIR/opt/heimgewebe/edge"
mkdir -p "$TEST_DIR/repo/edge"

LIVE_FILE="$TEST_DIR/opt/heimgewebe/edge/Caddyfile"
CANDIDATE_FILE="$TEST_DIR/repo/edge/Caddyfile.template"

echo "old_live_content" > "$LIVE_FILE"
echo "new_candidate_content" > "$CANDIDATE_FILE"

ORIGINAL_INODE=$(stat -c '%i' "$LIVE_FILE")

# Helper to run the sync logic
run_sync() {
    local expected_hash=$1
    local live=$2
    local cand=$3
    
    EXPECTED_LIVE_SHA256="$expected_hash" LIVE_FILE="$live" CANDIDATE_FILE="$cand" bash << 'RUNBOOK'
set -e
: "${EXPECTED_LIVE_SHA256:?Set the reviewed current live Caddyfile hash}"

if [ -f "$LIVE_FILE" ]; then
    CURRENT_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
else
    echo "ERROR: live Caddyfile is missing" >&2
    exit 1
fi

CANDIDATE_SHA256="$(sha256sum "$CANDIDATE_FILE" | awk '{print $1}')"

if [ "$CURRENT_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]; then
    echo "ERROR: Unexpected drift in live Caddyfile. Aborting." >&2
    exit 1
fi

if [ "$CURRENT_LIVE_SHA256" == "$CANDIDATE_SHA256" ]; then
    echo "No changes to sync."
    exit 0
fi

# Mock validation
echo "Mock validation OK"

# Backup
BACKUP_FILE="$LIVE_FILE.bak.mock"
cp -a "$LIVE_FILE" "$BACKUP_FILE"

# In-place sync
cat "$CANDIDATE_FILE" > "$LIVE_FILE"

POST_SYNC_HOST_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [ "$POST_SYNC_HOST_SHA256" != "$CANDIDATE_SHA256" ]; then
    echo "ERROR: Host file write failed or altered!" >&2
    exit 1
fi
RUNBOOK
}

TRUE_LIVE_HASH=$(sha256sum "$LIVE_FILE" | awk '{print $1}')

echo "--- Fall A: unerwartete Live-Drift ---"
if run_sync "wronghash" "$LIVE_FILE" "$CANDIDATE_FILE" 2>/dev/null; then
    echo "❌ Failed: Should abort on wrong expected hash"
    exit 1
else
    echo "✅ Aborted correctly"
fi

echo "--- Fall C: fehlende Live-Datei ---"
if run_sync "$TRUE_LIVE_HASH" "$TEST_DIR/missing" "$CANDIDATE_FILE" 2>/dev/null; then
    echo "❌ Failed: Should abort on missing file"
    exit 1
else
    echo "✅ Aborted correctly"
fi

echo "--- Fall B: echte beabsichtigte Aktualisierung ---"
if run_sync "$TRUE_LIVE_HASH" "$LIVE_FILE" "$CANDIDATE_FILE" >/dev/null; then
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

echo "== All runbook logic tests passed =="
