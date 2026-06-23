#!/usr/bin/env bash
set -euo pipefail

# Scripts for atomic, drift-safe Caddyfile sync
# Variables:
#   EXPECTED_LIVE_SHA256
#   LIVE_FILE (default: /opt/heimgewebe/edge/Caddyfile)
#   CANDIDATE_FILE (default: edge/Caddyfile.template)
#   CADDY_CONTAINER (default: edge-caddy)

LIVE_FILE="${LIVE_FILE:-/opt/heimgewebe/edge/Caddyfile}"
CANDIDATE_FILE="${CANDIDATE_FILE:-edge/Caddyfile.template}"
CADDY_CONTAINER="${CADDY_CONTAINER:-edge-caddy}"

: "${EXPECTED_LIVE_SHA256:?Set the reviewed current live Caddyfile hash}"

if [ ! -f "$LIVE_FILE" ]; then
    echo "ERROR: live Caddyfile is missing" >&2
    exit 1
fi

CURRENT_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
CANDIDATE_SHA256="$(sha256sum "$CANDIDATE_FILE" | awk '{print $1}')"

if [ "$CURRENT_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]; then
    echo "ERROR: Unexpected drift in live Caddyfile. Aborting." >&2
    exit 1
fi

if [ "$CURRENT_LIVE_SHA256" == "$CANDIDATE_SHA256" ]; then
    echo "No changes to sync."
    exit 0
fi

echo "Validating candidate with Caddy 2.8.4..."
docker run --rm \
  --network none \
  -v "$PWD:/repo:ro" \
  -w /repo \
  caddy:2.8.4 \
  caddy validate \
    --adapter caddyfile \
    --config "$CANDIDATE_FILE"

BACKUP_FILE="${LIVE_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
echo "Creating backup at $BACKUP_FILE"
cp -a "$LIVE_FILE" "$BACKUP_FILE"

# Trap for rollback
rollback() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "ERROR DETECTED ($exit_code). Initiating rollback..." >&2
        cat "$BACKUP_FILE" > "$LIVE_FILE"
        echo "Rollback: Restored $LIVE_FILE from $BACKUP_FILE" >&2
        
        # Verify restored state
        RESTORED_HASH="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
        if [ "$RESTORED_HASH" != "$CURRENT_LIVE_SHA256" ]; then
            echo "CRITICAL: Host file failed to rollback correctly!" >&2
        else
            echo "Rollback: Host file verified." >&2
        fi
        
        CONTAINER_RESTORED_HASH="$(docker compose exec -T "$CADDY_CONTAINER" sha256sum /etc/caddy/Caddyfile | awk '{print $1}')"
        if [ "$CONTAINER_RESTORED_HASH" != "$CURRENT_LIVE_SHA256" ]; then
            echo "CRITICAL: Container file failed to rollback correctly!" >&2
        else
            echo "Rollback: Container file verified." >&2
        fi
        
        docker compose exec -T "$CADDY_CONTAINER" caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile || true
        echo "Rollback complete. Do not reload if validation above failed." >&2
    fi
}

trap rollback EXIT

echo "Performing in-place sync..."
cat "$CANDIDATE_FILE" > "$LIVE_FILE"

POST_SYNC_HOST_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [ "$POST_SYNC_HOST_SHA256" != "$CANDIDATE_SHA256" ]; then
    echo "ERROR: Host file write failed or altered!" >&2
    exit 1
fi

CONTAINER_SHA256="$(
    docker compose exec -T "$CADDY_CONTAINER" \
      sha256sum /etc/caddy/Caddyfile \
      | awk '{print $1}'
)"
if [ "$CONTAINER_SHA256" != "$CANDIDATE_SHA256" ]; then
    echo "ERROR: Container file hash does not match candidate." >&2
    exit 1
fi

echo "Pre-reload container validation..."
docker compose exec -T "$CADDY_CONTAINER" \
  caddy validate \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile

echo "Sync and validation successful. Ready for reload."
# Clear trap on success
trap - EXIT
