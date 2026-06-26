#!/usr/bin/env bash
# Fail-closed Caddy Admin API boundary guard.
# Exit codes: 0=contract proven, 1=contract violated, 2=diagnosis impossible.
set -euo pipefail

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
EXPECTED_CONTAINER_ID=""
TMP_DIR=""

fail() {
  echo "BOUNDARY VIOLATION ($1): $2" >&2
  exit 1
}

sysfail() {
  echo "DIAGNOSTIC FAILURE ($1): $2" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || \
    sysfail "missing_command" "Required command not found: $1"
}

usage() {
  cat >&2 <<'USAGE'
Usage: check_admin_boundary.sh [--container-id CONTAINER_ID]
USAGE
}

is_container_id() {
  [[ "$1" =~ ^[[:xdigit:]]{12,64}$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container-id)
      [[ $# -ge 2 ]] || sysfail "argument" "--container-id requires a value"
      EXPECTED_CONTAINER_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      sysfail "argument" "Unknown argument: $1"
      ;;
  esac
done

if [[ -n "$EXPECTED_CONTAINER_ID" ]] && ! is_container_id "$EXPECTED_CONTAINER_ID"; then
  sysfail "container_id_syntax" "Invalid container ID syntax: $EXPECTED_CONTAINER_ID"
fi

require_cmd docker
require_cmd python3
require_cmd mktemp

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heimserver-admin-boundary.XXXXXX")"
cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

run_capture() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  "$@" >"$stdout_file" 2>"$stderr_file"
}

resolve_service_container_id() {
  local stdout_file stderr_file rc
  stdout_file="$(mktemp "$TMP_DIR/compose-ps.stdout.XXXXXX")"
  stderr_file="$(mktemp "$TMP_DIR/compose-ps.stderr.XXXXXX")"

  set +e
  run_capture "$stdout_file" "$stderr_file" compose ps --quiet "$CADDY_SERVICE"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    sed 's/^/compose ps stderr: /' "$stderr_file" >&2 || true
    sysfail "compose_ps" "docker compose ps failed (rc=$rc)"
  fi

  mapfile -t ids < <(sed '/^[[:space:]]*$/d' "$stdout_file")
  if [[ ${#ids[@]} -eq 0 ]]; then
    sysfail "container_identity_missing" \
      "No running container ID resolved for service $CADDY_SERVICE"
  fi
  if [[ ${#ids[@]} -ne 1 ]]; then
    fail "container_identity_ambiguous" \
      "Expected one container ID, found ${#ids[@]}"
  fi
  if ! is_container_id "${ids[0]}"; then
    sysfail "container_id_syntax" "Resolved container ID has invalid syntax: ${ids[0]}"
  fi
  printf '%s\n' "${ids[0]}"
}

CADDY_CONTAINER_ID="$(resolve_service_container_id)"
if [[ -n "$EXPECTED_CONTAINER_ID" && "$CADDY_CONTAINER_ID" != "$EXPECTED_CONTAINER_ID" ]]; then
  fail "container_identity_drift" \
    "Compose maps $CADDY_SERVICE to $CADDY_CONTAINER_ID, expected $EXPECTED_CONTAINER_ID"
fi
echo "ADMIN_CONTAINER_ID=$CADDY_CONTAINER_ID"

echo "== A. Containerlokale Admin-API erreichbar =="
EXEC_STDOUT="$(mktemp "$TMP_DIR/admin-probe.stdout.XXXXXX")"
EXEC_STDERR="$(mktemp "$TMP_DIR/admin-probe.stderr.XXXXXX")"
set +e
# shellcheck disable=SC2016
run_capture "$EXEC_STDOUT" "$EXEC_STDERR" \
  docker exec "$CADDY_CONTAINER_ID" sh -ec '
probe_url="http://127.0.0.1:2019/config/"
if command -v wget >/dev/null 2>&1; then
  wget -qO- -T 3 "$probe_url" >/dev/null
elif command -v curl >/dev/null 2>&1; then
  curl --fail --silent --max-time 3 "$probe_url" >/dev/null
else
  exit 2
fi
'
EXEC_RC=$?
set -e

if [[ $EXEC_RC -eq 2 ]]; then
  sysfail "no_http_client" \
    "Neither wget nor curl available inside the Caddy container"
elif [[ $EXEC_RC -ne 0 ]]; then
  fail "ADMIN_LOCAL_LOOPBACK" \
    "Admin API unreachable on 127.0.0.1:2019 (rc=$EXEC_RC)"
fi
echo "ADMIN_LOCAL_LOOPBACK=reachable"

echo "== B. Container-Listener-Bindung auf Port 2019 =="
PROC_STDOUT="$(mktemp "$TMP_DIR/proc-tcp.stdout.XXXXXX")"
PROC_STDERR="$(mktemp "$TMP_DIR/proc-tcp.stderr.XXXXXX")"
set +e
run_capture "$PROC_STDOUT" "$PROC_STDERR" \
  docker exec "$CADDY_CONTAINER_ID" sh -c \
  'cat /proc/net/tcp 2>/dev/null; printf "\n---TCP6---\n"; cat /proc/net/tcp6 2>/dev/null'
PROC_RC=$?
set -e
if [[ $PROC_RC -ne 0 ]]; then
  sed 's/^/proc read stderr: /' "$PROC_STDERR" >&2 || true
  sysfail "proc_tcp" "Failed to read container socket table (rc=$PROC_RC)"
fi
[[ -s "$PROC_STDOUT" ]] || sysfail "proc_tcp_empty" "Empty socket table"

set +e
BINDING_RESULT="$(python3 - "$PROC_STDOUT" <<'PY'
import ipaddress
import socket
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
parts = raw.split("---TCP6---")
tcp4 = parts[0].splitlines()
tcp6 = parts[1].splitlines() if len(parts) > 1 else []
port_hex = format(2019, "04X")
checked = 0
ipv4_loopback = 0
violations = []


def ipv4(hex_ip: str) -> str:
    raw_ip = bytes.fromhex(hex_ip)
    return str(ipaddress.ip_address(raw_ip[::-1]))


def ipv6(hex_ip: str) -> str:
    raw_ip = bytes.fromhex(hex_ip)
    network = b"".join(raw_ip[i:i + 4][::-1] for i in range(0, 16, 4))
    return str(ipaddress.ip_address(socket.inet_ntop(socket.AF_INET6, network)))


for family, lines, decode in (
    ("IPv4", tcp4, ipv4),
    ("IPv6", tcp6, ipv6),
):
    for line in lines:
        cols = line.split()
        if len(cols) < 4 or cols[0] == "sl" or cols[3] != "0A":
            continue
        local = cols[1]
        if ":" not in local:
            continue
        hex_ip, hex_port = local.rsplit(":", 1)
        if hex_port.upper() != port_hex:
            continue
        checked += 1
        try:
            address = decode(hex_ip)
        except Exception as exc:
            print(f"Parse error ({family}): {exc}", file=sys.stderr)
            sys.exit(2)
        if family == "IPv4":
            if address == "127.0.0.1":
                ipv4_loopback += 1
            else:
                violations.append(
                    f"IPv4 listener violates 127.0.0.1-only contract: {address}:2019"
                )
        else:
            violations.append(
                f"IPv6 listener violates 127.0.0.1-only contract: [{address}]:2019"
            )

if checked == 0:
    print("NO_LISTENER")
    sys.exit(2)
if violations:
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
if ipv4_loopback != 1:
    print("NO_IPV4_LOOPBACK")
    sys.exit(1)
print("127.0.0.1-only")
PY
)"
BINDING_RC=$?
set -e

if [[ "$BINDING_RESULT" == "NO_LISTENER" ]]; then
  fail "ADMIN_CONTAINER_NO_LISTENER" "No listener found on port 2019"
elif [[ "$BINDING_RESULT" == "NO_IPV4_LOOPBACK" ]]; then
  fail "ADMIN_CONTAINER_BINDING" "Expected exactly one 127.0.0.1:2019 listener"
elif [[ $BINDING_RC -eq 1 ]]; then
  fail "ADMIN_CONTAINER_BINDING" "Port 2019 violates the 127.0.0.1-only binding contract"
elif [[ $BINDING_RC -ne 0 ]]; then
  sysfail "proc_parse" "Failed to parse container socket table"
fi
echo "ADMIN_CONTAINER_BINDING=127.0.0.1-only"

echo "== C. Compose veröffentlicht Port 2019 nicht =="
COMPOSE_STDOUT="$(mktemp "$TMP_DIR/compose-config.stdout.XXXXXX")"
COMPOSE_STDERR="$(mktemp "$TMP_DIR/compose-config.stderr.XXXXXX")"
set +e
run_capture "$COMPOSE_STDOUT" "$COMPOSE_STDERR" compose config --format json
COMPOSE_RC=$?
set -e
if [[ $COMPOSE_RC -ne 0 ]]; then
  sed 's/^/compose config stderr: /' "$COMPOSE_STDERR" >&2 || true
  sysfail "compose_config" "docker compose config failed (rc=$COMPOSE_RC)"
fi

set +e
python3 - "$COMPOSE_STDOUT" "$CADDY_SERVICE" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(exc, file=sys.stderr)
    sys.exit(2)

service = sys.argv[2]
ports = data.get("services", {}).get(service, {}).get("ports", [])
for entry in ports:
    if isinstance(entry, dict):
        published = entry.get("published")
        if published is not None and int(published) == 2019:
            sys.exit(1)
    elif isinstance(entry, str):
        left = entry.rsplit("/", 1)[0].split(":")
        if left and left[-2 if len(left) > 1 else 0].strip() == "2019":
            sys.exit(1)
sys.exit(0)
PY
COMPOSE_PORT_RC=$?
set -e
if [[ $COMPOSE_PORT_RC -eq 1 ]]; then
  fail "ADMIN_COMPOSE_PUBLISHED_PORT" "Port 2019 is published by Compose"
elif [[ $COMPOSE_PORT_RC -ne 0 ]]; then
  sysfail "compose_json_invalid" "Compose config JSON is invalid"
fi
echo "ADMIN_COMPOSE_PUBLISHED_PORT=absent"

echo "== D. Runtime-Container veröffentlicht Port 2019 nicht =="
INSPECT_STDOUT="$(mktemp "$TMP_DIR/inspect.stdout.XXXXXX")"
INSPECT_STDERR="$(mktemp "$TMP_DIR/inspect.stderr.XXXXXX")"
set +e
run_capture "$INSPECT_STDOUT" "$INSPECT_STDERR" \
  docker inspect "$CADDY_CONTAINER_ID" --format '{{json .NetworkSettings.Ports}}'
INSPECT_RC=$?
set -e
if [[ $INSPECT_RC -ne 0 ]]; then
  sed 's/^/docker inspect stderr: /' "$INSPECT_STDERR" >&2 || true
  sysfail "docker_inspect" \
    "docker inspect failed for $CADDY_CONTAINER_ID (rc=$INSPECT_RC)"
fi

set +e
python3 - "$INSPECT_STDOUT" <<'PY'
import json
import sys
from pathlib import Path

try:
    ports = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except json.JSONDecodeError:
    sys.exit(2)

if ports is None:
    sys.exit(0)
for key, bindings in ports.items():
    if key.split("/", 1)[0] == "2019" and bindings:
        sys.exit(1)
sys.exit(0)
PY
INSPECT_PORT_RC=$?
set -e
if [[ $INSPECT_PORT_RC -eq 1 ]]; then
  fail "ADMIN_RUNTIME_PUBLISHED_PORT" \
    "Port 2019 is published in the resolved runtime container"
elif [[ $INSPECT_PORT_RC -ne 0 ]]; then
  sysfail "inspect_json_invalid" "docker inspect JSON is invalid"
fi
echo "ADMIN_RUNTIME_PUBLISHED_PORT=absent"

echo "== E. Kein Hostlistener auf Port 2019 =="
HOST_STDOUT="$(mktemp "$TMP_DIR/host-sockets.stdout.XXXXXX")"
HOST_STDERR="$(mktemp "$TMP_DIR/host-sockets.stderr.XXXXXX")"
if command -v ss >/dev/null 2>&1; then
  set +e
  run_capture "$HOST_STDOUT" "$HOST_STDERR" ss -H -ltn
  HOST_RC=$?
  set -e
elif command -v netstat >/dev/null 2>&1; then
  set +e
  run_capture "$HOST_STDOUT" "$HOST_STDERR" netstat -lnt
  HOST_RC=$?
  set -e
else
  sysfail "no_ss_netstat" "Neither ss nor netstat is available"
fi
if [[ $HOST_RC -ne 0 ]]; then
  sed 's/^/host socket stderr: /' "$HOST_STDERR" >&2 || true
  sysfail "host_socket_check" "Host listener inspection failed (rc=$HOST_RC)"
fi
if grep -Eq '(^|[[:space:]])([^[:space:]]*:)?2019([[:space:]]|$)' "$HOST_STDOUT"; then
  fail "ADMIN_HOST_LISTENER" "Host has a listener on port 2019"
fi

echo "ADMIN_HOST_LISTENER=absent"
echo "ADMIN_BOUNDARY_PROOF=PASS"
