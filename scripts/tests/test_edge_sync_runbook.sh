#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/edge/sync_caddyfile.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/edge" "$TEST_DIR/repo/edge"

export EDGE_DIR="$TEST_DIR/edge"
export COMPOSE_FILE="$EDGE_DIR/docker-compose.yml"
export LIVE_FILE="$EDGE_DIR/Caddyfile"
export CANDIDATE_FILE="$TEST_DIR/repo/edge/Caddyfile.template"
export LOCK_FILE="$TEST_DIR/sync.lock"
export ADMIN_BOUNDARY_CHECK="$TEST_DIR/mock_boundary.sh"
export CADDY_CONTRACT_VALIDATOR="$TEST_DIR/mock_contract.py"
export SYNC_EVENT_LOG="$TEST_DIR/events.log"
export DOCKER_LOG="$TEST_DIR/docker.log"
export CONTRACT_LOG="$TEST_DIR/contract.log"
export BOUNDARY_LOG="$TEST_DIR/boundary.log"
export STATE_DIR="$TEST_DIR/state"
export CADDY_IMAGE="caddy:2.8.4"

GOOD_ID="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
ALT_ID="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
export GOOD_ID ALT_ID

touch "$COMPOSE_FILE"
mkdir -p "$STATE_DIR"

cat >"$TEST_DIR/bin/cp" <<'MOCKCP'
#!/usr/bin/env bash
set -euo pipefail
destination="${!#}"

if [[ "$destination" == *.bak.* && "${FAIL_BACKUP_COPY:-0}" == "1" ]]; then
  printf 'partial-backup\n' >"$destination"
  exit 1
fi

/bin/cp "$@"

if [[ "$destination" == *.bak.* && "${CORRUPT_BACKUP_COPY:-0}" == "1" ]]; then
  printf 'backup-corruption\n' >>"$destination"
fi
MOCKCP
chmod +x "$TEST_DIR/bin/cp"

cat >"$TEST_DIR/bin/docker" <<'MOCKDOCKER'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$DOCKER_LOG"
printf '\n' >>"$DOCKER_LOG"

cmd="$1"
shift || true

counter() {
  name="$1"
  file="$STATE_DIR/$name.count"
  value="$(cat "$file" 2>/dev/null || echo 0)"
  value=$((value + 1))
  printf '%s\n' "$value" >"$file"
  printf '%s\n' "$value"
}

case "$cmd" in
  image)
    if [[ "$1" == "inspect" ]]; then
      [[ "${MOCK_IMAGE_MISSING:-0}" == "1" ]] && exit 1
      [[ "$2" == "${CADDY_IMAGE:-caddy:2.8.4}" ]] || exit 90
      exit 0
    fi
    ;;
  compose)
    if [[ "$*" == *"ps --quiet"* ]]; then
      n="$(counter compose_ps)"
      if [[ "${MOCK_PS_FAIL:-0}" == "1" ]]; then
        printf 'compose ps failed\n' >&2
        exit 7
      fi
      if [[ "${MOCK_NO_ID:-0}" == "1" ]]; then
        printf '\n'
      elif [[ "${MOCK_TWO_IDS:-0}" == "1" ]]; then
        printf '%s\n%s\n' "$GOOD_ID" "$ALT_ID"
      elif [[ "${MOCK_RECREATE_ON_RECHECK:-0}" == "1" && "$n" -ge 2 ]]; then
        printf '%s\n' "$ALT_ID"
      else
        printf '%s\n' "$GOOD_ID"
      fi
      if [[ -n "${MOCK_PS_STDERR:-}" ]]; then
        printf '%s\n' "$MOCK_PS_STDERR" >&2
      fi
      exit 0
    fi
    ;;
  exec)
    id="$1"
    shift || true
    if [[ "$id" != "$GOOD_ID" ]]; then
      printf 'unexpected exec id: %s\n' "$id" >&2
      exit 91
    fi
    if [[ "$*" == *"sha256sum /etc/caddy/Caddyfile"* ]]; then
      n="$(counter hash)"
      if [[ "${FAIL_PRE_CONTAINER_HASH:-0}" == "1" && "$n" -eq 1 ]]; then
        printf '%064d  /etc/caddy/Caddyfile\n' 0
      elif [[ "${FAIL_POST_CONTAINER_HASH:-0}" == "1" && "$n" -eq 2 ]]; then
        printf '%064d  /etc/caddy/Caddyfile\n' 0
      elif [[ "${FAIL_ROLLBACK_CONTAINER_HASH:-0}" == "1" && "$n" -ge 3 ]]; then
        printf '%064d  /etc/caddy/Caddyfile\n' 1
      else
        sha256sum "$LIVE_FILE"
      fi
      exit 0
    fi
    if [[ "$*" == *"caddy validate"* ]]; then
      n="$(counter exec_validate)"
      if [[ "${FAIL_POST_VALIDATE:-0}" == "1" && "$n" -eq 1 ]]; then
        printf 'post-write validation failed\n' >&2
        exit 1
      fi
      if [[ "${FAIL_ROLLBACK_VALIDATE:-0}" == "1" && "$n" -ge 2 ]]; then
        printf 'rollback validation failed\n' >&2
        exit 1
      fi
      printf 'exec validate ok\n'
      exit 0
    fi
    ;;
  run)
    if [[ "$*" == *"caddy validate"* ]]; then
      rc="${MOCK_SYNTAX_RC:-0}"
      [[ "$rc" != "0" ]] && printf 'syntax failed\n' >&2
      exit "$rc"
    fi
    if [[ "$*" == *"caddy adapt"* ]]; then
      rc="${MOCK_ADAPT_RC:-0}"
      if [[ -n "${MOCK_ADAPT_STDERR:-}" ]]; then
        printf '%s\n' "$MOCK_ADAPT_STDERR" >&2
      fi
      if [[ "$rc" != "0" ]]; then
        printf 'adapt failed\n' >&2
        exit "$rc"
      fi
      if [[ "${MOCK_ADAPT_EMPTY:-0}" == "1" ]]; then
        exit 0
      fi
      if [[ "${MOCK_ADAPT_INVALID_JSON:-0}" == "1" ]]; then
        printf 'not-json\n'
        exit 0
      fi
      printf '{"apps":{"http":{"servers":{}}}}\n'
      exit 0
    fi
    ;;
esac

printf 'unexpected docker command: %s %s\n' "$cmd" "$*" >&2
exit 99
MOCKDOCKER
chmod +x "$TEST_DIR/bin/docker"

cat >"$CADDY_CONTRACT_VALIDATOR" <<'MOCKCONTRACT'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

log = os.environ["CONTRACT_LOG"]
with open(log, "a", encoding="utf-8") as handle:
    handle.write(" ".join(sys.argv) + "\n")

if "--adapted-json" not in sys.argv:
    print("mock expected --adapted-json", file=sys.stderr)
    sys.exit(2)
adapted = Path(sys.argv[sys.argv.index("--adapted-json") + 1])

if os.environ.get("MUTATE_ORIGINAL_CANDIDATE") == "1":
    Path(os.environ["CANDIDATE_FILE"]).write_text("raced-content\n", encoding="utf-8")

if os.environ.get("MUTATE_SNAPSHOT") == "1":
    snapshot = adapted.with_name("Caddyfile")
    snapshot.chmod(0o644)
    snapshot.write_text("tampered-snapshot\n", encoding="utf-8")

rc = int(os.environ.get("MOCK_CONTRACT_RC", "0"))
if rc:
    print(f"mock contract rc={rc}", file=sys.stderr)
sys.exit(rc)
MOCKCONTRACT
chmod +x "$CADDY_CONTRACT_VALIDATOR"

cat >"$ADMIN_BOUNDARY_CHECK" <<'MOCKBOUNDARY'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$BOUNDARY_LOG"
printf '\n' >>"$BOUNDARY_LOG"
expected="${GOOD_ID:?}"
if [[ "$1" != "--container-id" || "$2" != "$expected" ]]; then
  echo "wrong boundary container id" >&2
  exit 2
fi
if ls "$LIVE_FILE.bak."* >/dev/null 2>&1; then
  echo "boundary ran after backup" >&2
  exit 99
fi
if [[ "${MUTATE_LIVE_AFTER_BOUNDARY:-0}" == "1" ]]; then
  printf 'drifted-live\n' >"$LIVE_FILE"
fi
if [[ "${MOCK_BOUNDARY_RC:-0}" != "0" ]]; then
  exit "$MOCK_BOUNDARY_RC"
fi
exit 0
MOCKBOUNDARY
chmod +x "$ADMIN_BOUNDARY_CHECK"

FAILURES=0
LAST_RC=0
LAST_OUTPUT=""
OLD_HASH=""

reset_case() {
  rm -f "$DOCKER_LOG" "$CONTRACT_LOG" "$BOUNDARY_LOG" "$SYNC_EVENT_LOG"
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
  rm -f "$LIVE_FILE".bak.*
  printf 'old-live\n' >"$LIVE_FILE"
  printf 'reviewed-content\n' >"$CANDIDATE_FILE"
  OLD_HASH="$(sha256sum "$LIVE_FILE" | awk '{print $1}')"
}

run_sync() {
  local actual_rc=0
  set +e
  LAST_OUTPUT="$(env \
    PATH="$TEST_DIR/bin:$PATH" \
    EXPECTED_LIVE_SHA256="$OLD_HASH" \
    EDGE_DIR="$EDGE_DIR" \
    COMPOSE_FILE="$COMPOSE_FILE" \
    LIVE_FILE="$LIVE_FILE" \
    CANDIDATE_FILE="$CANDIDATE_FILE" \
    LOCK_FILE="$LOCK_FILE" \
    ADMIN_BOUNDARY_CHECK="$ADMIN_BOUNDARY_CHECK" \
    CADDY_CONTRACT_VALIDATOR="$CADDY_CONTRACT_VALIDATOR" \
    SYNC_EVENT_LOG="$SYNC_EVENT_LOG" \
    DOCKER_LOG="$DOCKER_LOG" \
    CONTRACT_LOG="$CONTRACT_LOG" \
    BOUNDARY_LOG="$BOUNDARY_LOG" \
    STATE_DIR="$STATE_DIR" \
    GOOD_ID="$GOOD_ID" \
    ALT_ID="$ALT_ID" \
    CADDY_IMAGE="$CADDY_IMAGE" \
    "$@" \
    bash "$SYNC_SCRIPT" 2>&1)"
  actual_rc=$?
  set -e
  LAST_RC="$actual_rc"
}

expect_rc() {
  local desc="$1"
  local expected="$2"
  if [[ "$LAST_RC" != "$expected" ]]; then
    echo "FAIL [$desc]: expected rc $expected, got $LAST_RC"
    echo "$LAST_OUTPUT"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$desc]: rc $LAST_RC"
  fi
}

assert_file_content() {
  local desc="$1"
  local path="$2"
  local expected="$3"
  if [[ "$(cat "$path")" != "$expected" ]]; then
    echo "FAIL [$desc]: unexpected content in $path"
    printf 'expected: %s\nactual: %s\n' "$expected" "$(cat "$path")"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$desc]"
  fi
}

assert_no_backup() {
  local desc="$1"
  if compgen -G "$LIVE_FILE.bak.*" >/dev/null; then
    echo "FAIL [$desc]: backup exists"
    ls -l "$LIVE_FILE".bak.*
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$desc]: no backup"
  fi
}

assert_backup_exists() {
  local desc="$1"
  if compgen -G "$LIVE_FILE.bak.*" >/dev/null; then
    echo "PASS [$desc]: backup exists"
  else
    echo "FAIL [$desc]: expected backup"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_log_absent() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if [[ -f "$path" ]] && grep -qF -- "$pattern" "$path"; then
    echo "FAIL [$desc]: found $pattern in $path"
    cat "$path"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$desc]"
  fi
}

assert_log_present_count() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  local expected="$4"
  local actual=0
  if [[ -f "$path" ]]; then
    actual="$(grep -cF -- "$pattern" "$path" || true)"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [$desc]: expected $expected occurrences of $pattern, got $actual"
    [[ -f "$path" ]] && cat "$path"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$desc]"
  fi
}

echo "=== sync_caddyfile.sh behavior tests ==="

reset_case
run_sync LIVE_FILE="$EDGE_DIR/missing-Caddyfile"
expect_rc "missing live file fails closed" 1
assert_no_backup "missing live file"
assert_log_absent "missing live file skips Docker" "$DOCKER_LOG" "compose"

reset_case
run_sync EXPECTED_LIVE_SHA256="$(printf '%064d' 0)"
expect_rc "wrong reviewed live hash fails closed" 1
assert_no_backup "wrong reviewed live hash"
assert_file_content "wrong reviewed hash leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync FAIL_PRE_CONTAINER_HASH=1
expect_rc "pre-sync container hash drift fails closed" 1
assert_no_backup "pre-sync container hash drift"
assert_file_content "pre-sync container drift leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
exec 8>"$LOCK_FILE"
flock -n 8
run_sync
expect_rc "held sync lock fails closed" 1
assert_no_backup "held sync lock"
flock -u 8
exec 8>&-

reset_case
run_sync MOCK_SYNTAX_RC=42
expect_rc "syntax error maps to contract violation" 1
assert_log_absent "syntax error skips adapt" "$DOCKER_LOG" "caddy adapt"
assert_log_absent "syntax error skips contract" "$CONTRACT_LOG" "--adapted-json"
assert_log_absent "syntax error skips boundary" "$BOUNDARY_LOG" "--container-id"
assert_no_backup "syntax error"
assert_file_content "syntax error leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync MOCK_SYNTAX_RC=124
expect_rc "syntax validation timeout maps to diagnostic failure" 2
assert_no_backup "syntax validation timeout"

reset_case
run_sync MOCK_SYNTAX_RC=125
expect_rc "Docker start failure maps to diagnostic failure" 2
assert_no_backup "Docker start failure"

reset_case
run_sync MOCK_ADAPT_RC=42
expect_rc "adapt nonzero maps to diagnostic failure" 2
assert_log_absent "adapt failure skips contract" "$CONTRACT_LOG" "--adapted-json"
assert_log_absent "adapt failure skips boundary" "$BOUNDARY_LOG" "--container-id"
assert_no_backup "adapt failure"
assert_file_content "adapt failure leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync MOCK_ADAPT_EMPTY=1
expect_rc "empty adapt stdout maps to diagnostic failure" 2
assert_log_absent "empty adapt skips contract" "$CONTRACT_LOG" "--adapted-json"
assert_no_backup "empty adapt"

reset_case
run_sync MOCK_ADAPT_INVALID_JSON=1
expect_rc "invalid adapt JSON maps to diagnostic failure" 2
assert_log_absent "invalid adapt skips contract" "$CONTRACT_LOG" "--adapted-json"
assert_no_backup "invalid adapt"

reset_case
run_sync MUTATE_ORIGINAL_CANDIDATE=1
expect_rc "candidate race still writes reviewed snapshot" 0
assert_file_content "candidate race writes reviewed snapshot" "$LIVE_FILE" "reviewed-content"
assert_file_content "candidate source was raced after snapshot" "$CANDIDATE_FILE" "raced-content"

reset_case
run_sync MUTATE_SNAPSHOT=1
expect_rc "snapshot manipulation fails closed" 1
assert_log_absent "snapshot manipulation stops before boundary" "$BOUNDARY_LOG" "--container-id"
assert_no_backup "snapshot manipulation"
assert_file_content "snapshot manipulation leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync MUTATE_LIVE_AFTER_BOUNDARY=1
expect_rc "live drift before write fails closed" 1
assert_no_backup "live drift before backup"
assert_file_content "external live drift was not overwritten" "$LIVE_FILE" "drifted-live"

reset_case
run_sync MOCK_RECREATE_ON_RECHECK=1
expect_rc "container recreate before mutation fails closed" 1
assert_no_backup "container recreate"
assert_file_content "container recreate leaves live untouched" "$LIVE_FILE" "old-live"
assert_log_absent "container recreate never execs new ID" "$DOCKER_LOG" "$ALT_ID sha256sum"

reset_case
run_sync MOCK_CONTRACT_RC=1
expect_rc "contract exit 1 is preserved" 1
assert_log_absent "contract exit 1 skips boundary" "$BOUNDARY_LOG" "--container-id"
assert_no_backup "contract exit 1"
assert_file_content "contract exit 1 leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync MOCK_CONTRACT_RC=2
expect_rc "contract exit 2 is preserved" 2
assert_log_absent "contract exit 2 skips boundary" "$BOUNDARY_LOG" "--container-id"
assert_no_backup "contract exit 2"

reset_case
run_sync MOCK_BOUNDARY_RC=1
expect_rc "boundary exit 1 is preserved" 1
assert_no_backup "boundary exit 1"
assert_file_content "boundary exit 1 leaves live untouched" "$LIVE_FILE" "old-live"

reset_case
run_sync MOCK_BOUNDARY_RC=2
expect_rc "boundary exit 2 is preserved" 2
assert_no_backup "boundary exit 2"

reset_case
run_sync CORRUPT_BACKUP_COPY=1
expect_rc "corrupt pre-write backup fails closed" 1
assert_no_backup "corrupt pre-write backup is removed"
assert_file_content "corrupt backup leaves live untouched" "$LIVE_FILE" "old-live"
assert_log_absent "corrupt backup stops before write" "$SYNC_EVENT_LOG" "write"

reset_case
run_sync FAIL_BACKUP_COPY=1
expect_rc "partial backup copy maps to diagnostic failure" 2
assert_no_backup "partial pre-write backup is removed"
assert_file_content "partial backup copy leaves live untouched" "$LIVE_FILE" "old-live"
assert_log_absent "partial backup stops before write" "$SYNC_EVENT_LOG" "write"

reset_case
LIVE_INODE_BEFORE="$(stat -c '%i' "$LIVE_FILE")"
run_sync MOCK_PS_STDERR="compose warning" MOCK_ADAPT_STDERR="adapt warning"
expect_rc "success path tolerates structured stdout with stderr warnings" 0
assert_backup_exists "success path"
assert_file_content "success path writes candidate snapshot" "$LIVE_FILE" "reviewed-content"
LIVE_INODE_AFTER="$(stat -c '%i' "$LIVE_FILE")"
if [[ "$LIVE_INODE_AFTER" == "$LIVE_INODE_BEFORE" ]]; then
  echo "PASS [success path preserves live-file inode]"
else
  echo "FAIL [success path changed live-file inode]"
  FAILURES=$((FAILURES + 1))
fi
BACKUP_PATH="$(compgen -G "$LIVE_FILE.bak.*" | head -n 1)"
if [[ "$(sha256sum "$BACKUP_PATH" | awk '{print $1}')" != "$OLD_HASH" ]]; then
  echo "FAIL [verified backup hash does not match original live hash]"
  FAILURES=$((FAILURES + 1))
fi
assert_log_present_count "success path adapts exactly once" "$DOCKER_LOG" "caddy adapt" 1
EXPECTED_EVENTS=$'snapshot\nsyntax\nadapt\ncontract\nboundary\nsnapshot-recheck\nlive-recheck\ncontainer-recheck\nbackup\nwrite\npost-write-container-recheck\nvalidate'
if [[ "$(cat "$SYNC_EVENT_LOG")" == "$EXPECTED_EVENTS" ]]; then
  echo "PASS [success event order]"
else
  echo "FAIL [success event order]"
  cat "$SYNC_EVENT_LOG"
  FAILURES=$((FAILURES + 1))
fi

reset_case
run_sync FAIL_POST_CONTAINER_HASH=1
expect_rc "post-write container hash mismatch rolls back" 1
assert_backup_exists "rollback on post-write hash"
assert_file_content "rollback restores live file" "$LIVE_FILE" "old-live"

reset_case
run_sync FAIL_POST_VALIDATE=1 FAIL_ROLLBACK_VALIDATE=1
expect_rc "unverifiable rollback returns 255" 255
assert_backup_exists "unverifiable rollback"
assert_file_content "unverifiable rollback attempted in-place restore" "$LIVE_FILE" "old-live"

reset_case
run_sync MOCK_NO_ID=1
expect_rc "no container ID is diagnostic failure" 2
assert_log_absent "no ID skips exec" "$DOCKER_LOG" "exec"
assert_no_backup "no ID"

reset_case
run_sync MOCK_TWO_IDS=1
expect_rc "two container IDs are contract violation" 1
assert_log_absent "two IDs skip exec" "$DOCKER_LOG" "exec"
assert_no_backup "two IDs"

if [[ $FAILURES -eq 0 ]]; then
  echo "== All sync behavior tests passed =="
else
  echo "== FAILED: $FAILURES sync behavior test(s) failed ==" >&2
  exit 1
fi
