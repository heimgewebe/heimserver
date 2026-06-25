#!/usr/bin/env bash
# Drift-safe in-place Caddyfile synchronization for a single-file bind mount.
# Exit codes: 0=success, 1=contract/drift violation, 2=diagnostic failure,
# 255=rollback could not be fully verified.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8.4}"
LIVE_FILE="${LIVE_FILE:-$EDGE_DIR/Caddyfile}"
CANDIDATE_FILE="${CANDIDATE_FILE:-$REPO_ROOT/edge/Caddyfile.template}"
LOCK_FILE="${LOCK_FILE:-/run/lock/heimserver-edge-caddy-sync.lock}"

ADMIN_BOUNDARY_CHECK="${ADMIN_BOUNDARY_CHECK:-$SCRIPT_DIR/check_admin_boundary.sh}"
CADDY_CONTRACT_VALIDATOR="${CADDY_CONTRACT_VALIDATOR:-$SCRIPT_DIR/validate_caddy_contract.py}"
CADDY_REDIRECT_VALIDATOR="${CADDY_REDIRECT_VALIDATOR:-$SCRIPT_DIR/validate_caddy_redirect.py}"

: "${EXPECTED_LIVE_SHA256:?Set the reviewed current live Caddyfile hash}"

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "ERROR: another edge sync is active" >&2
  exit 1
fi

[[ -f "$LIVE_FILE" ]] || {
  echo "ERROR: live Caddyfile is missing" >&2
  exit 1
}
[[ -f "$CANDIDATE_FILE" ]] || {
  echo "ERROR: candidate Caddyfile is missing" >&2
  exit 1
}

CURRENT_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$CURRENT_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]]; then
  echo "ERROR: unexpected drift in live Caddyfile" >&2
  exit 1
fi

CURRENT_CONTAINER_SHA256="$(
  compose exec -T "$CADDY_SERVICE" sha256sum /etc/caddy/Caddyfile |
    awk '{print $1}'
)"
if [[ "$CURRENT_CONTAINER_SHA256" != "$CURRENT_LIVE_SHA256" ]]; then
  echo "ERROR: host and container Caddyfiles already diverge" >&2
  exit 1
fi

CANDIDATE_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/heimserver-caddy-candidate.XXXXXX")"
BACKUP_FILE=""
MUTATION_STARTED=0

cleanup_or_rollback() {
  local rc=$?
  trap - EXIT

  if [[ $rc -ne 0 && $MUTATION_STARTED -eq 1 ]]; then
    local rollback_ok=1
    echo "ERROR DETECTED ($rc). Initiating rollback..." >&2

    if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
      echo "CRITICAL: rollback backup is unavailable" >&2
      rollback_ok=0
    elif ! cat "$BACKUP_FILE" >"$LIVE_FILE"; then
      echo "CRITICAL: could not restore host file" >&2
      rollback_ok=0
    fi

    local restored_hash=""
    restored_hash="$(sha256sum "$LIVE_FILE" | awk '{print $1}' || true)"
    if [[ "$restored_hash" != "$CURRENT_LIVE_SHA256" ]]; then
      echo "CRITICAL: host rollback hash mismatch" >&2
      rollback_ok=0
    fi

    local container_restored_hash=""
    container_restored_hash="$(
      compose exec -T "$CADDY_SERVICE" sha256sum /etc/caddy/Caddyfile |
        awk '{print $1}' || true
    )"
    if [[ "$container_restored_hash" != "$CURRENT_LIVE_SHA256" ]]; then
      echo "CRITICAL: container rollback hash mismatch" >&2
      rollback_ok=0
    fi

    if ! compose exec -T "$CADDY_SERVICE" \
      caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile; then
      echo "CRITICAL: rollback Caddy validation failed" >&2
      rollback_ok=0
    fi

    rm -f -- "$CANDIDATE_SNAPSHOT"

    if [[ $rollback_ok -eq 1 ]]; then
      echo "Rollback verified." >&2
      exit "$rc"
    fi

    echo "CRITICAL: rollback could not be fully verified" >&2
    exit 255
  fi

  rm -f -- "$CANDIDATE_SNAPSHOT"
  exit "$rc"
}
trap cleanup_or_rollback EXIT

cp -- "$CANDIDATE_FILE" "$CANDIDATE_SNAPSHOT"
chmod 0644 "$CANDIDATE_SNAPSHOT"
CANDIDATE_SHA256="$(sha256sum "$CANDIDATE_SNAPSHOT" | awk '{print $1}')"

if [[ "$CURRENT_LIVE_SHA256" == "$CANDIDATE_SHA256" ]]; then
  echo "No changes to sync."
  exit 0
fi

SNAPSHOT_DIR="$(dirname -- "$CANDIDATE_SNAPSHOT")"
SNAPSHOT_NAME="$(basename -- "$CANDIDATE_SNAPSHOT")"

echo "Validating candidate snapshot syntax with $CADDY_IMAGE..."
set +e
docker run --rm \
  --pull=never \
  --network none \
  -v "$SNAPSHOT_DIR:/candidate:ro" \
  "$CADDY_IMAGE" \
  caddy validate \
  --adapter caddyfile \
  --config "/candidate/$SNAPSHOT_NAME"
SYNTAX_RC=$?
set -e
if [[ $SYNTAX_RC -ne 0 ]]; then
  echo "ERROR: candidate syntax validation failed (rc=$SYNTAX_RC)" >&2
  exit "$SYNTAX_RC"
fi

echo "Running structural contract validation on candidate snapshot..."
set +e
python3 "$CADDY_CONTRACT_VALIDATOR" --caddyfile "$CANDIDATE_SNAPSHOT"
CONTRACT_RC=$?
set -e
if [[ $CONTRACT_RC -ne 0 ]]; then
  echo "ERROR: candidate contract validation failed (rc=$CONTRACT_RC)" >&2
  exit "$CONTRACT_RC"
fi

echo "Validating exact internal API redirect on candidate snapshot..."
set +e
python3 "$CADDY_REDIRECT_VALIDATOR" --caddyfile "$CANDIDATE_SNAPSHOT"
REDIRECT_RC=$?
set -e
if [[ $REDIRECT_RC -ne 0 ]]; then
  echo "ERROR: candidate redirect validation failed (rc=$REDIRECT_RC)" >&2
  exit "$REDIRECT_RC"
fi

echo "Running Admin Boundary Guard..."
set +e
bash "$ADMIN_BOUNDARY_CHECK"
GUARD_RC=$?
set -e
if [[ $GUARD_RC -ne 0 ]]; then
  echo "ERROR: Admin boundary guard failed (rc=$GUARD_RC)" >&2
  exit "$GUARD_RC"
fi

PRE_WRITE_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$PRE_WRITE_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]]; then
  echo "ERROR: live Caddyfile changed during validation (TOCTOU)" >&2
  exit 1
fi

BACKUP_FILE="${LIVE_FILE}.bak.$(date -u +%Y%m%dT%H%M%S%NZ)"
[[ ! -e "$BACKUP_FILE" ]] || {
  echo "ERROR: backup path already exists" >&2
  exit 1
}

cp -a "$LIVE_FILE" "$BACKUP_FILE"
MUTATION_STARTED=1
cat "$CANDIDATE_SNAPSHOT" >"$LIVE_FILE"

POST_SYNC_HOST_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
if [[ "$POST_SYNC_HOST_SHA256" != "$CANDIDATE_SHA256" ]]; then
  echo "ERROR: host write does not match validated snapshot" >&2
  exit 1
fi

CONTAINER_SHA256="$(
  compose exec -T "$CADDY_SERVICE" sha256sum /etc/caddy/Caddyfile |
    awk '{print $1}'
)"
if [[ "$CONTAINER_SHA256" != "$CANDIDATE_SHA256" ]]; then
  echo "ERROR: container file does not match validated snapshot" >&2
  exit 1
fi

compose exec -T "$CADDY_SERVICE" \
  caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile

MUTATION_STARTED=0
echo "Sync and validation successful. Ready for reload."
