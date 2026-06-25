#!/usr/bin/env bash
# sync_caddyfile.sh — Drift-safe in-place Caddyfile sync for a single-file bind mount
# Pre-mutation gate order:
#   1. Hash + container-identity check
#   2. Candidate syntactic validation (caddy validate)
#   3. Candidate structural contract (validate_caddy_contract.py)
#   4. Admin boundary guard (check_admin_boundary.sh)
#   5. TOCTOU hash re-check
#   6. Backup + in-place mutation
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
LIVE_FILE="${LIVE_FILE:-$EDGE_DIR/Caddyfile}"
CANDIDATE_FILE="${CANDIDATE_FILE:-$REPO_ROOT/edge/Caddyfile.template}"
LOCK_FILE="${LOCK_FILE:-/run/lock/heimserver-edge-caddy-sync.lock}"

ADMIN_BOUNDARY_CHECK="${ADMIN_BOUNDARY_CHECK:-$SCRIPT_DIR/check_admin_boundary.sh}"
CADDY_CONTRACT_VALIDATOR="${CADDY_CONTRACT_VALIDATOR:-$REPO_ROOT/scripts/edge/validate_caddy_contract.py}"

: "${EXPECTED_LIVE_SHA256:?Set the reviewed current live Caddyfile hash}"

# Exclusive lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "ERROR: another edge sync is active" >&2
    exit 1
fi

if [[ ! -f "$LIVE_FILE" ]]; then
    echo "ERROR: live Caddyfile is missing" >&2
    exit 1
fi

# ── 1. Hash check ─────────────────────────────────────────────────────────────
CURRENT_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$CURRENT_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]]; then
    echo "ERROR: Unexpected drift in live Caddyfile. Aborting." >&2
    exit 1
fi

CANDIDATE_SHA256="$(sha256sum "$CANDIDATE_FILE" | awk '{print $1}')"
if [[ "$CURRENT_LIVE_SHA256" == "$CANDIDATE_SHA256" ]]; then
    echo "No changes to sync."
    exit 0
fi

CURRENT_CONTAINER_SHA256="$(
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" exec -T "$CADDY_SERVICE" \
    sha256sum /etc/caddy/Caddyfile | awk '{print $1}'
)"
if [[ "$CURRENT_CONTAINER_SHA256" != "$CURRENT_LIVE_SHA256" ]]; then
  echo "ERROR: host and container Caddyfiles already diverge" >&2
  exit 1
fi

# ── 2. Candidate syntactic validation ────────────────────────────────────────
echo "Validating candidate syntax with Caddy 2.8.4..."
CANDIDATE_DIR="$(dirname -- "$CANDIDATE_FILE")"
CANDIDATE_NAME="$(basename -- "$CANDIDATE_FILE")"

docker run --rm \
  --pull=never \
  --network none \
  -v "$CANDIDATE_DIR:/candidate:ro" \
  caddy:2.8.4 \
  caddy validate \
    --adapter caddyfile \
    --config "/candidate/$CANDIDATE_NAME"

# ── 3. Candidate structural contract ─────────────────────────────────────────
echo "Running structural contract validation on candidate..."
set +e
python3 "$CADDY_CONTRACT_VALIDATOR" --caddyfile "$CANDIDATE_FILE"
CONTRACT_RC=$?
set -e
if [[ $CONTRACT_RC -ne 0 ]]; then
    echo "ERROR: Candidate failed structural contract validation (rc=$CONTRACT_RC). Aborting." >&2
    exit "$CONTRACT_RC"
fi

# ── 4. Admin boundary guard ───────────────────────────────────────────────────
echo "Running Admin Boundary Guard..."
set +e
bash "$ADMIN_BOUNDARY_CHECK"
GUARD_RC=$?
set -e
if [[ $GUARD_RC -ne 0 ]]; then
    echo "ERROR: Admin boundary guard failed (rc=$GUARD_RC). Aborting." >&2
    exit "$GUARD_RC"
fi

# ── 5. TOCTOU re-check right before backup and write ─────────────────────────
PRE_WRITE_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$PRE_WRITE_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]]; then
  echo "ERROR: live Caddyfile changed during candidate validation (TOCTOU)" >&2
  exit 1
fi

# ── 6. Backup + in-place mutation ─────────────────────────────────────────────
BACKUP_FILE="${LIVE_FILE}.bak.$(date -u +%Y%m%dT%H%M%S%NZ)"
if [[ -e "$BACKUP_FILE" ]]; then
  echo "ERROR: backup path already exists" >&2
  exit 1
fi

echo "Creating backup at $BACKUP_FILE"
cp -a "$LIVE_FILE" "$BACKUP_FILE"

rollback() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR DETECTED ($exit_code). Initiating rollback..." >&2
        trap - EXIT
        local rollback_ok=1

        if ! cat "$BACKUP_FILE" > "$LIVE_FILE"; then
            echo "CRITICAL: could not restore host file" >&2
            rollback_ok=0
        fi

        echo "Rollback: Restored $LIVE_FILE from $BACKUP_FILE" >&2

        RESTORED_HASH="$(sha256sum "$LIVE_FILE" | awk '{print $1}' || true)"
        if [[ "$RESTORED_HASH" != "$CURRENT_LIVE_SHA256" ]]; then
            echo "CRITICAL: Host file failed to rollback correctly!" >&2
            rollback_ok=0
        fi

        CONTAINER_RESTORED_HASH="$(
          docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" \
            exec -T "$CADDY_SERVICE" sha256sum /etc/caddy/Caddyfile \
          | awk '{print $1}' || true
        )"
        if [[ "$CONTAINER_RESTORED_HASH" != "$CURRENT_LIVE_SHA256" ]]; then
            echo "CRITICAL: Container file failed to rollback correctly!" >&2
            rollback_ok=0
        fi

        if ! docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" \
            exec -T "$CADDY_SERVICE" \
            caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile; then
            echo "CRITICAL: Rollback container validation failed!" >&2
            rollback_ok=0
        fi

        if [[ "$rollback_ok" == 1 ]]; then
            echo "Rollback verified." >&2
            exit "$exit_code"
        else
            echo "CRITICAL: rollback could not be fully verified." >&2
            exit 255
        fi
    fi
}
trap rollback EXIT

echo "Performing in-place sync..."
cat "$CANDIDATE_FILE" > "$LIVE_FILE"

POST_SYNC_HOST_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$POST_SYNC_HOST_SHA256" != "$CANDIDATE_SHA256" ]]; then
    echo "ERROR: Host file write failed or altered!" >&2
    exit 1
fi

CONTAINER_SHA256="$(
    docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" exec -T "$CADDY_SERVICE" \
      sha256sum /etc/caddy/Caddyfile | awk '{print $1}'
)"
if [[ "$CONTAINER_SHA256" != "$CANDIDATE_SHA256" ]]; then
    echo "ERROR: Container file hash does not match candidate." >&2
    exit 1
fi

echo "Pre-reload container validation..."
docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" exec -T "$CADDY_SERVICE" \
  caddy validate \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile

echo "Sync and validation successful. Ready for reload."
trap - EXIT
