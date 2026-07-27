#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/edge/sync_caddyfile.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

LIVE_FILE="$TEST_DIR/Caddyfile"
CANDIDATE_FILE="$TEST_DIR/Caddyfile.template"
LOCK_FILE="$TEST_DIR/sync.lock"
DOCKER_LOG="$TEST_DIR/docker.log"

printf 'live-sentinel\n' >"$LIVE_FILE"
printf 'candidate-sentinel\n' >"$CANDIDATE_FILE"

mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected docker call: %s\n' "$*" >>"${DOCKER_LOG:?}"
exit 99
EOF
chmod +x "$TEST_DIR/bin/docker"

set +e
OUTPUT="$(
  env \
    PATH="$TEST_DIR/bin:$PATH" \
    DOCKER_LOG="$DOCKER_LOG" \
    LIVE_FILE="$LIVE_FILE" \
    CANDIDATE_FILE="$CANDIDATE_FILE" \
    LOCK_FILE="$LOCK_FILE" \
    EXPECTED_LIVE_SHA256="$(sha256sum "$LIVE_FILE" | awk '{print $1}')" \
    bash "$SYNC_SCRIPT" 2>&1
)"
STATUS=$?
set -e

[[ "$STATUS" -eq 2 ]]
grep -Fq "Blocked: Heimserver is retired" <<<"$OUTPUT"
[[ "$(cat "$LIVE_FILE")" == "live-sentinel" ]]
[[ "$(cat "$CANDIDATE_FILE")" == "candidate-sentinel" ]]
[[ ! -e "$LOCK_FILE" ]]
[[ ! -e "$DOCKER_LOG" ]]
if compgen -G "$LIVE_FILE.bak.*" >/dev/null; then
  echo "retired Caddy sync created a backup before its guard" >&2
  exit 1
fi

echo "PASS: retired Caddy sync blocks before every deployment operation"
