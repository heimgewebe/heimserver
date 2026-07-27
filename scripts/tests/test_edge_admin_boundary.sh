#!/usr/bin/env bash
# Unit tests for check_admin_boundary.sh.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../edge/check_admin_boundary.sh"

FAILURES=0
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"
DOCKER_LOG="$TEST_DIR/docker.log"
export DOCKER_LOG

GOOD_ID="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
ALT_ID="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
SHORT_ID="0123456789ab"
export GOOD_ID ALT_ID SHORT_ID

PROC_IPV4_LOOPBACK="  sl  local_address rem_addr   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0"
PROC_IPV6_LOOPBACK="  sl  local_address                         remote_address                   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000001000000:07E3 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000:00000000 00000000     0        0 12346 1 0000000000000000 100 0 0 10 0"
PROC_WILDCARD="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 00000000:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12347 1 0000000000000000 100 0 0 10 0"
PROC_CONTAINER_IP="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 020014AC:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12348 1 0000000000000000 100 0 0 10 0"
PROC_NO_PORT_2019="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 0100007F:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12349 1 0000000000000000 100 0 0 10 0"

GOOD_PROC="$PROC_IPV4_LOOPBACK"$'\n'"---TCP6---"
GOOD_COMPOSE_JSON='{"services":{"caddy":{"ports":[{"published":80,"target":80,"protocol":"tcp"},{"published":443,"target":443,"protocol":"tcp"}]}}}'
GOOD_INSPECT_JSON='{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"80"}],"443/tcp":[{"HostIp":"0.0.0.0","HostPort":"443"}]}'
GOOD_SS_OUT="LISTEN 0 128 0.0.0.0:80 0.0.0.0:*"
SS_OUT="$GOOD_SS_OUT"
SS_RC=0

write_docker_mock() {
  cat >"$TEST_DIR/bin/docker" <<'DOCKEREOF'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$DOCKER_LOG"
printf '\n' >>"$DOCKER_LOG"

cmd="$1"
shift || true

case "$cmd" in
  compose)
    if [[ "$*" == *"ps --quiet"* ]]; then
      if [[ "${MOCK_COMPOSE_PS_FAIL:-0}" == "1" ]]; then
        printf '%s\n' "${MOCK_COMPOSE_PS_STDERR:-compose ps failed}" >&2
        exit 7
      fi
      printf '%s\n' "${MOCK_COMPOSE_PS_STDOUT-$GOOD_ID}"
      if [[ -n "${MOCK_COMPOSE_PS_STDERR:-}" ]]; then
        printf '%s\n' "$MOCK_COMPOSE_PS_STDERR" >&2
      fi
      exit 0
    fi
    if [[ "$*" == *"config --format json"* ]]; then
      if [[ "${MOCK_COMPOSE_CONFIG_FAIL:-0}" == "1" ]]; then
        printf '%s\n' "${MOCK_COMPOSE_CONFIG_STDERR:-compose config failed}" >&2
        exit 8
      fi
      printf '%s\n' "${MOCK_COMPOSE_JSON-$GOOD_COMPOSE_JSON}"
      if [[ -n "${MOCK_COMPOSE_CONFIG_STDERR:-}" ]]; then
        printf '%s\n' "$MOCK_COMPOSE_CONFIG_STDERR" >&2
      fi
      exit 0
    fi
    ;;
  exec)
    id="$1"
    shift || true
    if [[ "$id" != "${EXPECTED_RUNTIME_ID:-$GOOD_ID}" ]]; then
      printf 'wrong runtime id: %s\n' "$id" >&2
      exit 44
    fi
    if [[ "$*" == *"sh -ec"* ]]; then
      exit "${MOCK_ADMIN_PROBE_RC:-0}"
    fi
    if [[ "$*" == *"/proc/net/tcp"* ]]; then
      printf '%s\n' "${MOCK_PROC_TCP-$GOOD_PROC}"
      if [[ -n "${MOCK_PROC_STDERR:-}" ]]; then
        printf '%s\n' "$MOCK_PROC_STDERR" >&2
      fi
      exit "${MOCK_PROC_RC:-0}"
    fi
    ;;
  inspect)
    id="$1"
    if [[ "$id" != "${EXPECTED_RUNTIME_ID:-$GOOD_ID}" ]]; then
      printf 'wrong inspect id: %s\n' "$id" >&2
      exit 45
    fi
    if [[ "${MOCK_INSPECT_FAIL:-0}" == "1" ]]; then
      printf '%s\n' "${MOCK_INSPECT_STDERR:-inspect failed}" >&2
      exit 9
    fi
    printf '%s\n' "${MOCK_INSPECT_JSON-$GOOD_INSPECT_JSON}"
    if [[ -n "${MOCK_INSPECT_STDERR:-}" ]]; then
      printf '%s\n' "$MOCK_INSPECT_STDERR" >&2
    fi
    exit 0
    ;;
  run)
    echo "unexpected docker run" >&2
    exit 99
    ;;
esac

printf 'unexpected docker command: %s %s\n' "$cmd" "$*" >&2
exit 98
DOCKEREOF
  chmod +x "$TEST_DIR/bin/docker"
}

write_ss_mock() {
  local output="$1"
  local rc="${2:-0}"
  cat >"$TEST_DIR/bin/ss" <<SSEOF
#!/usr/bin/env bash
printf '%s\n' ${output@Q}
exit $rc
SSEOF
  chmod +x "$TEST_DIR/bin/ss"
}

run_test() {
  local test_num="$1"
  local description="$2"
  local expected_rc="$3"
  local expected_pattern="${4:-}"
  shift 4 || true
  local envvars=("$@")

  write_docker_mock
  write_ss_mock "$SS_OUT" "$SS_RC"
  true >"$DOCKER_LOG"

  local actual_rc=0 out
  out="$(env \
    PATH="$TEST_DIR/bin:$PATH" \
    EDGE_DIR="/opt/heimgewebe/edge" \
    COMPOSE_FILE="/opt/heimgewebe/edge/docker-compose.yml" \
    ALLOW_HISTORICAL_HOST_READ=1 \
    GOOD_ID="$GOOD_ID" \
    ALT_ID="$ALT_ID" \
    SHORT_ID="$SHORT_ID" \
    GOOD_PROC="$GOOD_PROC" \
    GOOD_COMPOSE_JSON="$GOOD_COMPOSE_JSON" \
    GOOD_INSPECT_JSON="$GOOD_INSPECT_JSON" \
    "${envvars[@]}" \
    bash "$GUARD_SCRIPT" "${GUARD_ARGS[@]}" 2>&1)" || actual_rc=$?

  if [[ "$actual_rc" != "$expected_rc" ]]; then
    echo "FAIL $test_num: $description"
    echo "  expected exit $expected_rc, got $actual_rc"
    echo "  output: $out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -n "$expected_pattern" ]] && ! grep -qF "$expected_pattern" <<<"$out"; then
    echo "FAIL $test_num: $description"
    echo "  expected output to contain: $expected_pattern"
    echo "  output: $out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ "$expected_rc" == "0" ]]; then
    if ! grep -qF "ADMIN_BOUNDARY_PROOF=PASS" <<<"$out"; then
      echo "FAIL $test_num: success without proof marker"
      FAILURES=$((FAILURES + 1))
      return
    fi
    if grep -qi '"admin"' <<<"$out"; then
      echo "FAIL $test_num: admin response leaked"
      FAILURES=$((FAILURES + 1))
      return
    fi
  elif grep -qF "ADMIN_BOUNDARY_PROOF=PASS" <<<"$out"; then
    echo "FAIL $test_num: failure emitted proof marker"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS $test_num: $description (exit $actual_rc)"
}

assert_no_runtime_calls() {
  local desc="$1"
  if grep -Eq '(^| )exec |(^| )inspect ' "$DOCKER_LOG"; then
    echo "FAIL: $desc made runtime docker calls"
    cat "$DOCKER_LOG"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: $desc made no runtime docker calls"
  fi
}

assert_runtime_id_only() {
  local expected="$1"
  if grep -E '(^| )exec ' "$DOCKER_LOG" | grep -vF "$expected" >/dev/null; then
    echo "FAIL: docker exec used an unexpected container ID"
    cat "$DOCKER_LOG"
    FAILURES=$((FAILURES + 1))
  elif grep -E '(^| )inspect ' "$DOCKER_LOG" | grep -vF "$expected" >/dev/null; then
    echo "FAIL: docker inspect used an unexpected container ID"
    cat "$DOCKER_LOG"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: runtime commands used only $expected"
  fi
}

echo "=== Admin Boundary Guard Tests ==="

GUARD_ARGS=()
run_test 1 "no Compose container ID -> diagnostic failure" 2 "container_identity_missing" \
  "MOCK_COMPOSE_PS_STDOUT="
assert_no_runtime_calls "no-ID case"

GUARD_ARGS=()
run_test 2 "two Compose container IDs -> contract violation" 1 "container_identity_ambiguous" \
  "MOCK_COMPOSE_PS_STDOUT=$GOOD_ID"$'\n'"$ALT_ID"
assert_no_runtime_calls "ambiguous-ID case"

GUARD_ARGS=()
run_test 3 "one ID -> all runtime checks use that exact ID" 0 ""
assert_runtime_id_only "$GOOD_ID"

GUARD_ARGS=()
run_test 4 "compose ps warning on stderr does not corrupt stdout ID" 0 "" \
  "MOCK_COMPOSE_PS_STDERR=warning from compose"
assert_runtime_id_only "$GOOD_ID"

GUARD_ARGS=(--container-id "$GOOD_ID")
run_test 5 "explicit matching container ID is accepted" 0 ""
assert_runtime_id_only "$GOOD_ID"

GUARD_ARGS=(--container-id "$ALT_ID")
run_test 6 "explicit container ID drift fails closed" 1 "container_identity_drift"
assert_no_runtime_calls "explicit-drift case"

GUARD_ARGS=(--container-id "not-a-container")
run_test 7 "invalid explicit container ID syntax -> diagnostic failure" 2 "container_id_syntax"

GUARD_ARGS=()
run_test 8 "local Admin API unreachable -> contract violation" 1 "ADMIN_LOCAL_LOOPBACK" \
  "MOCK_ADMIN_PROBE_RC=1"

GUARD_ARGS=()
run_test 9 "no HTTP client in container -> diagnostic failure" 2 "no_http_client" \
  "MOCK_ADMIN_PROBE_RC=2"

GUARD_ARGS=()
run_test 10 "Compose config command fails -> diagnostic failure" 2 "compose_config" \
  "MOCK_COMPOSE_CONFIG_FAIL=1"

GUARD_ARGS=()
run_test 11 "Compose JSON invalid -> diagnostic failure" 2 "compose_json_invalid" \
  "MOCK_COMPOSE_JSON=not-json"

GUARD_ARGS=()
run_test 12 "Compose publishes 2019 -> contract violation" 1 "ADMIN_COMPOSE_PUBLISHED_PORT" \
  "MOCK_COMPOSE_JSON={\"services\":{\"caddy\":{\"ports\":[{\"published\":2019,\"target\":2019,\"protocol\":\"tcp\"}]}}}"

GUARD_ARGS=()
run_test 13 "Compose config warning on stderr keeps valid JSON parse" 0 "" \
  "MOCK_COMPOSE_CONFIG_STDERR=compose warning"

GUARD_ARGS=()
run_test 14 "docker inspect fails -> diagnostic failure" 2 "docker_inspect" \
  "MOCK_INSPECT_FAIL=1"

GUARD_ARGS=()
run_test 15 "docker inspect JSON invalid -> diagnostic failure" 2 "inspect_json_invalid" \
  "MOCK_INSPECT_JSON=bad-json"

GUARD_ARGS=()
run_test 16 "runtime publishes 2019 -> contract violation" 1 "ADMIN_RUNTIME_PUBLISHED_PORT" \
  "MOCK_INSPECT_JSON={\"2019/tcp\":[{\"HostIp\":\"0.0.0.0\",\"HostPort\":\"2019\"}]}"

SS_OUT="LISTEN 0 128 127.0.0.1:2019 0.0.0.0:*"
GUARD_ARGS=()
run_test 17 "host listener on 2019 -> contract violation" 1 "ADMIN_HOST_LISTENER"
SS_OUT="$GOOD_SS_OUT"

GUARD_ARGS=()
run_test 18 "no container listener on 2019 -> contract violation" 1 "ADMIN_CONTAINER_NO_LISTENER" \
  "MOCK_PROC_TCP=$PROC_NO_PORT_2019"$'\n'"---TCP6---"

GUARD_ARGS=()
run_test 19 "container listener on wildcard -> contract violation" 1 "ADMIN_CONTAINER_BINDING" \
  "MOCK_PROC_TCP=$PROC_WILDCARD"$'\n'"---TCP6---"

GUARD_ARGS=()
run_test 20 "container listener on container IP -> contract violation" 1 "ADMIN_CONTAINER_BINDING" \
  "MOCK_PROC_TCP=$PROC_CONTAINER_IP"$'\n'"---TCP6---"

GUARD_ARGS=()
run_test 21 "IPv6-only loopback does not satisfy explicit IPv4 contract" 1 "ADMIN_CONTAINER_BINDING" \
  "MOCK_PROC_TCP="$'\n'"---TCP6---"$'\n'"$PROC_IPV6_LOOPBACK"

if [[ $FAILURES -eq 0 ]]; then
  echo "== All Admin Boundary Guard tests passed =="
else
  echo "== FAILED: $FAILURES admin boundary test(s) failed ==" >&2
  exit 1
fi
