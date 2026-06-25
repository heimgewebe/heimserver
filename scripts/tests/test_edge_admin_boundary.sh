#!/usr/bin/env bash
# test_edge_admin_boundary.sh — Unit tests for check_admin_boundary.sh
# Exit codes of the guard: 0=OK, 1=violation, 2=diagnostic failure
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../edge/check_admin_boundary.sh"

FAILURES=0

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# ── Mock infrastructure ────────────────────────────────────────────────────────
mkdir -p "$TEST_DIR/bin"

# ── /proc/net/tcp snippets for container binding tests ─────────────────────────
# IPv4 LISTEN format: sl local_address rem_addr state uid ...
# local_address: HHHHHHHH:PPPP where IP is little-endian 4-byte hex, port is big-endian
# 0100007F = 127.0.0.1 (loopback), 07E3 = port 2019
# 00000000 = 0.0.0.0 (wildcard)
# AC140002 = 172.20.0.2 (example container IP)
PROC_LOOPBACK_ONLY="  sl  local_address rem_addr   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0"

PROC_IPV6_LOOPBACK="  sl  local_address                         remote_address                   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000001000000:07E3 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12346 1 0000000000000000 100 0 0 10 0"

# shellcheck disable=SC2034
PROC_IPV4_AND_IPV6_LOOPBACK="$PROC_LOOPBACK_ONLY"$'\n'"$PROC_IPV6_LOOPBACK"

PROC_WILDCARD="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 00000000:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12347 1 0000000000000000 100 0 0 10 0"

PROC_CONTAINER_IP="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 020014AC:07E3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12348 1 0000000000000000 100 0 0 10 0"

PROC_NO_PORT_2019="  sl  local_address rem_addr   st tx_queue rx_queue tr queue tx_queue retrnsmt   uid  timeout inode
   0: 0100007F:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12349 1 0000000000000000 100 0 0 10 0"

# Write shared mock docker
write_docker_mock() {
  cat >"$TEST_DIR/bin/docker" <<'DOCKEREOF'
#!/usr/bin/env bash
# Env vars controlling mock behavior:
#   MOCK_EXEC_RC     — exit code for "compose exec -T caddy sh" (default 0)
#   MOCK_COMPOSE_JSON — raw JSON for "compose config --format json"
#   MOCK_INSPECT_JSON — raw JSON for "docker inspect edge-caddy --format {{json .NetworkSettings.Ports}}"
#   MOCK_PROC_TCP    — content returned for the /proc/net/tcp read command
#   MOCK_DOCKER_RC   — override all docker exit codes
CMD="$1"; shift

if [[ "${MOCK_DOCKER_RC:-}" != "" ]]; then
  exit "${MOCK_DOCKER_RC}"
fi

case "$CMD" in
  compose)
    # "docker compose ... exec -T caddy sh -ec ..."
    if [[ "$*" == *"exec -T"*"sh -ec"* ]]; then
      exit "${MOCK_EXEC_RC:-0}"
    fi
    # "docker compose ... exec -T caddy sh -c 'cat /proc/net/tcp...'"
    if [[ "$*" == *"exec -T"*"cat /proc/net/tcp"* ]]; then
      printf '%s\n' "${MOCK_PROC_TCP:-}"
      exit 0
    fi
    # "docker compose ... config --format json"
    if [[ "$*" == *"config --format json"* ]]; then
      if [[ "${MOCK_COMPOSE_JSON_FAIL:-0}" == "1" ]]; then exit 1; fi
      mock_value="${MOCK_COMPOSE_JSON-}"
      if [[ -z "$mock_value" ]]; then
        mock_value='{}'
      fi
      printf '%s\n' "$mock_value"
      exit 0
    fi
    # Passthrough compose ps
    if [[ "$*" == *"ps --quiet"* ]]; then
      echo "fakeid123"
      exit 0
    fi
    exit 0
    ;;
  inspect)
    if [[ "${MOCK_INSPECT_FAIL:-0}" == "1" ]]; then exit 1; fi
    printf '%s\n' "${MOCK_INSPECT_JSON:-null}"
    exit 0
    ;;
  run)
    # No docker run should be called — flag it
    echo "ERROR: unexpected docker run call — no probe containers allowed" >&2
    exit 99
    ;;
  *)
    echo "ERROR: unexpected docker command: $CMD $*" >&2
    exit 1
    ;;
esac
DOCKEREOF
  chmod +x "$TEST_DIR/bin/docker"
}

write_ss_mock() {
  local output="$1"
  local rc="${2:-0}"
  printf '#!/usr/bin/env bash\n' >"$TEST_DIR/bin/ss"
  printf 'printf '\''%%s\\n'\'' %q\n' "$output" >>"$TEST_DIR/bin/ss"
  printf 'exit %d\n' "$rc" >>"$TEST_DIR/bin/ss"
  chmod +x "$TEST_DIR/bin/ss"
}

write_netstat_mock() {
  local output="$1"
  printf '#!/usr/bin/env bash\n' >"$TEST_DIR/bin/netstat"
  printf 'printf '\''%%s\\n'\'' %q\n' "$output" >>"$TEST_DIR/bin/netstat"
  printf 'exit 0\n' >>"$TEST_DIR/bin/netstat"
  chmod +x "$TEST_DIR/bin/netstat"
}

# ── Test runner ────────────────────────────────────────────────────────────────
run_test() {
  local test_num="$1"
  local description="$2"
  local expected_rc="$3"
  shift 3
  # remaining args are env var assignments: KEY=VALUE
  local envvars=("$@")

  write_docker_mock

  local actual_rc=0
  local out
  out="$(env \
    PATH="$TEST_DIR/bin:$PATH" \
    EDGE_DIR="/opt/heimgewebe/edge" \
    COMPOSE_FILE="/opt/heimgewebe/edge/docker-compose.yml" \
    "${envvars[@]}" \
    bash "$GUARD_SCRIPT" 2>&1)" || actual_rc=$?

  # Check no docker run was triggered
  if echo "$out" | grep -q "unexpected docker run"; then
    echo "  FAIL: docker run (probe container) was triggered — not allowed"
    FAILURES=$((FAILURES + 1))
    return
  fi

  if [[ "$actual_rc" != "$expected_rc" ]]; then
    echo "❌ Test $test_num: $description"
    echo "   Expected exit $expected_rc, got $actual_rc"
    echo "   Output: $out"
    FAILURES=$((FAILURES + 1))
  else
    echo "✅ Test $test_num: $description (exit $actual_rc)"
    # Additional checks for success case
    if [[ "$expected_rc" == "0" ]]; then
      if ! echo "$out" | grep -q "ADMIN_BOUNDARY_PROOF=PASS"; then
        echo "   FAIL: ADMIN_BOUNDARY_PROOF=PASS not in output on success"
        FAILURES=$((FAILURES + 1))
      fi
      # Verify no admin response data leaked
      if echo "$out" | grep -qi '"admin"'; then
        echo "   FAIL: Admin API response data leaked into output"
        FAILURES=$((FAILURES + 1))
      fi
    else
      if echo "$out" | grep -q "ADMIN_BOUNDARY_PROOF=PASS"; then
        echo "   FAIL: ADMIN_BOUNDARY_PROOF=PASS must not appear on failure"
        FAILURES=$((FAILURES + 1))
      fi
    fi
  fi
}

# Base environment that yields a passing state
GOOD_COMPOSE_JSON='{"services":{"caddy":{"ports":[]}}}'
GOOD_INSPECT_JSON='{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"80"}]}'
GOOD_SS_OUT="LISTEN 0 128 0.0.0.0:80 0.0.0.0:*"
GOOD_PROC="$PROC_LOOPBACK_ONLY"$'\n'"---TCP6---"

write_ss_mock "$GOOD_SS_OUT"

echo "=== Admin Boundary Guard Tests ==="
echo ""

# 1. Fully safe state → 0
run_test 1 "vollständig sicherer Zustand → 0" 0 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 2. Local API not reachable (exec returns 1) → 1
run_test 2 "lokale Admin-API nicht erreichbar → 1" 1 \
  "MOCK_EXEC_RC=1" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 3. No HTTP client in container (exec returns 2) → 2
run_test 3 "kein HTTP-Client im Container → 2" 2 \
  "MOCK_EXEC_RC=2" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 4. Compose config command fails → 2
run_test 4 "compose config Befehl scheitert → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON_FAIL=1" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 5. Compose JSON invalid → 2
run_test 5 "compose JSON ungültig → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=not-json{{{" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 6. Compose publishes 2019 → 1
COMPOSE_WITH_2019='{"services":{"caddy":{"ports":[{"published":2019,"target":2019,"protocol":"tcp"}]}}}'
run_test 6 "Compose veröffentlicht Port 2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$COMPOSE_WITH_2019" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 7. docker inspect fails → 2
run_test 7 "docker inspect scheitert → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_FAIL=1"

# 8. docker inspect JSON invalid → 2
run_test 8 "docker inspect JSON ungültig → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=bad{{{json"

# 9. Runtime container publishes 2019 → 1
INSPECT_WITH_2019='{"2019/tcp":[{"HostIp":"0.0.0.0","HostPort":"2019"}]}'
run_test 9 "Runtime-Container veröffentlicht Port 2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$INSPECT_WITH_2019"

# 10. ss fails → 2
write_ss_mock "" 1
run_test 10 "ss scheitert → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"
write_ss_mock "$GOOD_SS_OUT"

# 11. Host listener on 127.0.0.1:2019 → 1
write_ss_mock "LISTEN 0 128 127.0.0.1:2019 0.0.0.0:*"
run_test 11 "Hostlistener auf 127.0.0.1:2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"
write_ss_mock "$GOOD_SS_OUT"

# 12. Host listener on 0.0.0.0:2019 → 1
write_ss_mock "LISTEN 0 128 0.0.0.0:2019 0.0.0.0:*"
run_test 12 "Hostlistener auf 0.0.0.0:2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$GOOD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"
write_ss_mock "$GOOD_SS_OUT"

# 13. Container has no listener on 2019 → 1
NO_LISTENER="$PROC_NO_PORT_2019"$'\n'"---TCP6---"
run_test 13 "Container hat keinen Listener auf 2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$NO_LISTENER" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 14. Container listener on 0.0.0.0:2019 → 1
WILDCARD_PROC="$PROC_WILDCARD"$'\n'"---TCP6---"
run_test 14 "Containerlistener auf 0.0.0.0:2019 → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$WILDCARD_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 15. Container listener on container IP → 1
CONTAINER_IP_PROC="$PROC_CONTAINER_IP"$'\n'"---TCP6---"
run_test 15 "Containerlistener auf Container-IP → 1" 1 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$CONTAINER_IP_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 16. Only IPv4 loopback → 0
IPV4_ONLY="$PROC_LOOPBACK_ONLY"$'\n'"---TCP6---"
run_test 16 "ausschließlich IPv4-Loopback → 0" 0 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$IPV4_ONLY" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 17. Only IPv6 loopback → 0
IPV6_ONLY=$'\n'"---TCP6---"$'\n'"$PROC_IPV6_LOOPBACK"
run_test 17 "ausschließlich IPv6-Loopback → 0" 0 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$IPV6_ONLY" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 18. IPv4 and IPv6 loopback together → 0
BOTH_LOOPBACK="$PROC_LOOPBACK_ONLY"$'\n'"---TCP6---"$'\n'"$PROC_IPV6_LOOPBACK"
run_test 18 "IPv4 und IPv6 Loopback gemeinsam → 0" 0 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$BOTH_LOOPBACK" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 19. Socket data missing/unparseable → 2
EMPTY_PROC=""
run_test 19 "Socketdaten fehlen → 2" 2 \
  "MOCK_EXEC_RC=0" \
  "MOCK_PROC_TCP=$EMPTY_PROC" \
  "MOCK_COMPOSE_JSON=$GOOD_COMPOSE_JSON" \
  "MOCK_INSPECT_JSON=$GOOD_INSPECT_JSON"

# 20. Verify success markers only in success case (covered by run_test's checks above)
echo "✅ Test 20: Erfolgsmarker nur im echten Erfolgsfall vorhanden (via Tests 1-19)"

# 21. No admin response data in output (covered by run_test's ADMIN_BOUNDARY_PROOF check)
echo "✅ Test 21: Keine Admin-Antwortdaten im Output (via Tests 1-19)"

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "== All Admin Boundary Guard tests passed =="
else
  echo "== FAILED: $FAILURES test(s) failed =="
  exit 1
fi
