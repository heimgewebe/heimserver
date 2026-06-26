#!/usr/bin/env bash
# Drift-safe in-place Caddyfile synchronization for a single-file bind mount.
# Exit codes: 0=success/no-op, 1=contract or drift violation,
# 2=diagnosis impossible, 255=rollback could not be fully verified.
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

: "${EXPECTED_LIVE_SHA256:?Set the reviewed current live Caddyfile hash}"

SNAPSHOT_ROOT=""
CANDIDATE_SNAPSHOT=""
ADAPTED_JSON=""
BACKUP_FILE=""
INITIAL_LIVE_SHA256=""
CANDIDATE_SHA256=""
ADAPTED_SHA256=""
CADDY_CONTAINER_ID=""
NO_CHANGES=0
MUTATION_STARTED=0

record_event() {
  if [[ -n "${SYNC_EVENT_LOG:-}" ]]; then
    printf '%s\n' "$1" >>"$SYNC_EVENT_LOG"
  fi
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

sysfail() {
  echo "ERROR: $1" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || sysfail "required command not found: $1"
}

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

is_container_id() {
  [[ "$1" =~ ^[[:xdigit:]]{12,64}$ ]]
}

run_capture() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  "$@" >"$stdout_file" 2>"$stderr_file"
}

resolve_caddy_container_id() {
  local stdout_file stderr_file rc
  stdout_file="$(mktemp "$SNAPSHOT_ROOT/compose-ps.stdout.XXXXXX")"
  stderr_file="$(mktemp "$SNAPSHOT_ROOT/compose-ps.stderr.XXXXXX")"

  set +e
  run_capture "$stdout_file" "$stderr_file" compose ps --quiet "$CADDY_SERVICE"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    sed 's/^/compose ps stderr: /' "$stderr_file" >&2 || true
    sysfail "docker compose ps failed for service $CADDY_SERVICE (rc=$rc)"
  fi

  mapfile -t ids < <(sed '/^[[:space:]]*$/d' "$stdout_file")
  if [[ ${#ids[@]} -eq 0 ]]; then
    sysfail "no running container ID resolved for service $CADDY_SERVICE"
  fi
  if [[ ${#ids[@]} -ne 1 ]]; then
    fail "expected exactly one container ID for service $CADDY_SERVICE, found ${#ids[@]}"
  fi
  if ! is_container_id "${ids[0]}"; then
    sysfail "resolved container ID has unexpected syntax: ${ids[0]}"
  fi

  printf '%s\n' "${ids[0]}"
}

confirm_same_container() {
  local phase="$1"
  local current_id
  current_id="$(resolve_caddy_container_id)"
  if [[ "$current_id" != "$CADDY_CONTAINER_ID" ]]; then
    fail "Caddy container identity changed during $phase: expected $CADDY_CONTAINER_ID, got $current_id"
  fi
}

same_container_status() {
  local current_id
  current_id="$(resolve_caddy_container_id 2>/dev/null)" || return 1
  [[ "$current_id" == "$CADDY_CONTAINER_ID" ]]
}

container_caddyfile_hash() {
  local stdout_file stderr_file rc
  stdout_file="$(mktemp "$SNAPSHOT_ROOT/container-hash.stdout.XXXXXX")"
  stderr_file="$(mktemp "$SNAPSHOT_ROOT/container-hash.stderr.XXXXXX")"

  set +e
  run_capture "$stdout_file" "$stderr_file" \
    docker exec "$CADDY_CONTAINER_ID" sha256sum /etc/caddy/Caddyfile
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    sed 's/^/docker exec stderr: /' "$stderr_file" >&2 || true
    sysfail "failed to hash Caddyfile inside container $CADDY_CONTAINER_ID (rc=$rc)"
  fi
  awk '{print $1; exit}' "$stdout_file"
}

verify_snapshot_hash() {
  local phase="$1"
  local actual
  actual="$(hash_file "$CANDIDATE_SNAPSHOT")"
  if [[ "$actual" != "$CANDIDATE_SHA256" ]]; then
    fail "candidate snapshot changed during $phase"
  fi
}

verify_adapted_hash() {
  local phase="$1"
  local actual
  actual="$(hash_file "$ADAPTED_JSON")"
  if [[ "$actual" != "$ADAPTED_SHA256" ]]; then
    fail "adapted Caddy JSON changed during $phase"
  fi
}

verify_live_hash() {
  local phase="$1"
  local actual
  actual="$(hash_file "$LIVE_FILE")"
  if [[ "$actual" != "$EXPECTED_LIVE_SHA256" ]]; then
    fail "live Caddyfile changed during $phase"
  fi
}

cleanup_or_rollback() {
  local rc=$?
  trap - EXIT

  if [[ $rc -ne 0 && $MUTATION_STARTED -eq 1 ]]; then
    local rollback_ok=1 restored_hash="" container_restored_hash=""
    echo "ERROR DETECTED ($rc). Initiating in-place rollback..." >&2

    if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
      echo "CRITICAL: rollback backup is unavailable" >&2
      rollback_ok=0
    elif ! cat "$BACKUP_FILE" >"$LIVE_FILE"; then
      echo "CRITICAL: could not restore host file in place" >&2
      rollback_ok=0
    fi

    restored_hash="$(hash_file "$LIVE_FILE" || true)"
    if [[ "$restored_hash" != "$INITIAL_LIVE_SHA256" ]]; then
      echo "CRITICAL: host rollback hash mismatch" >&2
      rollback_ok=0
    fi

    if ! same_container_status; then
      echo "CRITICAL: container identity changed before rollback verification" >&2
      rollback_ok=0
    fi

    container_restored_hash="$(container_caddyfile_hash 2>/dev/null || true)"
    if [[ -z "$container_restored_hash" || "$container_restored_hash" != "$INITIAL_LIVE_SHA256" ]]; then
      echo "CRITICAL: container rollback hash mismatch" >&2
      rollback_ok=0
    fi

    if ! docker exec "$CADDY_CONTAINER_ID" \
      caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile; then
      echo "CRITICAL: rollback Caddy validation failed" >&2
      rollback_ok=0
    fi

    rm -rf -- "$SNAPSHOT_ROOT"

    if [[ $rollback_ok -eq 1 ]]; then
      echo "Rollback verified." >&2
      exit "$rc"
    fi

    echo "CRITICAL: rollback could not be fully verified" >&2
    exit 255
  fi

  rm -rf -- "$SNAPSHOT_ROOT"
  exit "$rc"
}

require_cmd docker
require_cmd python3
require_cmd sha256sum
require_cmd awk
require_cmd flock
require_cmd mktemp

umask 077
SNAPSHOT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/heimserver-caddy-snapshot.XXXXXX")"
chmod 0700 "$SNAPSHOT_ROOT"
trap cleanup_or_rollback EXIT

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  fail "another edge sync is active"
fi

[[ -f "$LIVE_FILE" ]] || fail "live Caddyfile is missing"
[[ -f "$CANDIDATE_FILE" ]] || sysfail "candidate Caddyfile is missing or not a regular file"

CADDY_CONTAINER_ID="$(resolve_caddy_container_id)"
echo "CADDY_CONTAINER_ID=$CADDY_CONTAINER_ID"

INITIAL_LIVE_SHA256="$(hash_file "$LIVE_FILE")"
if [[ "$INITIAL_LIVE_SHA256" != "$EXPECTED_LIVE_SHA256" ]]; then
  fail "unexpected drift in live Caddyfile"
fi

CURRENT_CONTAINER_SHA256="$(container_caddyfile_hash)"
if [[ "$CURRENT_CONTAINER_SHA256" != "$INITIAL_LIVE_SHA256" ]]; then
  fail "host and container Caddyfiles already diverge"
fi

CANDIDATE_SNAPSHOT="$SNAPSHOT_ROOT/Caddyfile"
ADAPTED_JSON="$SNAPSHOT_ROOT/Caddyfile.adapted.json"
cp -- "$CANDIDATE_FILE" "$CANDIDATE_SNAPSHOT"
chmod 0444 "$CANDIDATE_SNAPSHOT"
CANDIDATE_SHA256="$(hash_file "$CANDIDATE_SNAPSHOT")"

if [[ "$INITIAL_LIVE_SHA256" == "$CANDIDATE_SHA256" ]]; then
  NO_CHANGES=1
fi

if ! docker image inspect "$CADDY_IMAGE" >/dev/null 2>&1; then
  sysfail "Caddy Docker image not found locally: $CADDY_IMAGE"
fi

echo "Validating candidate snapshot syntax with $CADDY_IMAGE..."
set +e
docker run --rm \
  --pull=never \
  --network none \
  -v "$SNAPSHOT_ROOT:/candidate:ro" \
  "$CADDY_IMAGE" \
  caddy validate \
  --adapter caddyfile \
  --config /candidate/Caddyfile
SYNTAX_RC=$?
set -e
if [[ $SYNTAX_RC -ne 0 ]]; then
  fail "candidate syntax validation failed (rc=$SYNTAX_RC)"
fi
record_event "syntax"

echo "Adapting candidate snapshot once with $CADDY_IMAGE..."
ADAPT_STDERR="$SNAPSHOT_ROOT/caddy-adapt.stderr"
set +e
docker run --rm \
  --pull=never \
  --network none \
  -v "$SNAPSHOT_ROOT:/candidate:ro" \
  "$CADDY_IMAGE" \
  caddy adapt \
  --adapter caddyfile \
  --config /candidate/Caddyfile \
  >"$ADAPTED_JSON" \
  2>"$ADAPT_STDERR"
ADAPT_RC=$?
set -e
if [[ $ADAPT_RC -ne 0 ]]; then
  sed 's/^/caddy adapt stderr: /' "$ADAPT_STDERR" >&2 || true
  sysfail "caddy adapt failed (rc=$ADAPT_RC)"
fi
[[ -s "$ADAPTED_JSON" ]] || sysfail "caddy adapt produced empty JSON"
python3 - "$ADAPTED_JSON" <<'PY' || sysfail "caddy adapt output is not valid JSON"
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    json.load(handle)
PY
chmod 0444 "$ADAPTED_JSON"
ADAPTED_SHA256="$(hash_file "$ADAPTED_JSON")"
record_event "adapt"

echo "Running canonical Caddy contract validation on adapted JSON..."
set +e
python3 "$CADDY_CONTRACT_VALIDATOR" --adapted-json "$ADAPTED_JSON"
CONTRACT_RC=$?
set -e
if [[ $CONTRACT_RC -eq 1 || $CONTRACT_RC -eq 2 ]]; then
  exit "$CONTRACT_RC"
elif [[ $CONTRACT_RC -ne 0 ]]; then
  sysfail "candidate contract validator returned unexpected rc=$CONTRACT_RC"
fi
record_event "contract"

verify_snapshot_hash "contract validation"
verify_adapted_hash "contract validation"

echo "Running Admin Boundary Guard on resolved container..."
set +e
bash "$ADMIN_BOUNDARY_CHECK" --container-id "$CADDY_CONTAINER_ID"
GUARD_RC=$?
set -e
if [[ $GUARD_RC -eq 1 || $GUARD_RC -eq 2 ]]; then
  exit "$GUARD_RC"
elif [[ $GUARD_RC -ne 0 ]]; then
  sysfail "Admin boundary guard returned unexpected rc=$GUARD_RC"
fi
record_event "boundary"

verify_snapshot_hash "boundary validation"
verify_adapted_hash "boundary validation"
record_event "snapshot-recheck"

verify_live_hash "validation"
record_event "live-recheck"

confirm_same_container "pre-write recheck"
record_event "container-recheck"

verify_snapshot_hash "pre-write recheck"
verify_adapted_hash "pre-write recheck"

if [[ $NO_CHANGES -eq 1 ]]; then
  echo "No changes to sync; full read-only proof chain passed."
  exit 0
fi

LIVE_DIR="$(dirname -- "$LIVE_FILE")"
LIVE_BASE="$(basename -- "$LIVE_FILE")"
BACKUP_FILE="$(mktemp "$LIVE_DIR/$LIVE_BASE.bak.XXXXXX")" || sysfail "could not allocate backup file"
cp -p -- "$LIVE_FILE" "$BACKUP_FILE"
record_event "backup"

MUTATION_STARTED=1
cat "$CANDIDATE_SNAPSHOT" >"$LIVE_FILE"
record_event "write"

POST_SYNC_HOST_SHA256="$(hash_file "$LIVE_FILE")"
if [[ "$POST_SYNC_HOST_SHA256" != "$CANDIDATE_SHA256" ]]; then
  fail "host write does not match validated snapshot"
fi

confirm_same_container "post-write recheck"
record_event "post-write-container-recheck"

CONTAINER_SHA256="$(container_caddyfile_hash)"
if [[ "$CONTAINER_SHA256" != "$CANDIDATE_SHA256" ]]; then
  fail "container file does not match validated snapshot"
fi

set +e
docker exec "$CADDY_CONTAINER_ID" \
  caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile
POST_VALIDATE_RC=$?
set -e
if [[ $POST_VALIDATE_RC -ne 0 ]]; then
  fail "post-write Caddy validation failed (rc=$POST_VALIDATE_RC)"
fi
record_event "validate"

MUTATION_STARTED=0
echo "Sync and validation successful. Ready for manual reload."
