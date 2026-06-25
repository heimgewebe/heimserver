#!/usr/bin/env bash
# Fail-closed Caddy Admin API boundary guard.
# Exit codes: 0=contract proven, 1=contract violated, 2=diagnosis impossible.
set -euo pipefail

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"

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

require_cmd docker
require_cmd python3

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

set +e
CONTAINER_IDS_RAW="$(compose ps --quiet "$CADDY_SERVICE" 2>&1)"
CONTAINER_IDS_RC=$?
set -e
if [[ $CONTAINER_IDS_RC -ne 0 ]]; then
  sysfail "compose_ps" "docker compose ps failed (rc=$CONTAINER_IDS_RC)"
fi

mapfile -t CADDY_CONTAINER_IDS < <(
  printf '%s\n' "$CONTAINER_IDS_RAW" | sed '/^[[:space:]]*$/d'
)

if [[ ${#CADDY_CONTAINER_IDS[@]} -eq 0 ]]; then
  sysfail "container_identity_missing" \
    "No running container ID resolved for service $CADDY_SERVICE"
elif [[ ${#CADDY_CONTAINER_IDS[@]} -ne 1 ]]; then
  fail "container_identity_ambiguous" \
    "Expected one container ID, found ${#CADDY_CONTAINER_IDS[@]}"
fi

CADDY_CONTAINER_ID="${CADDY_CONTAINER_IDS[0]}"
echo "ADMIN_CONTAINER_ID=$CADDY_CONTAINER_ID"

echo "== A. Containerlokale Admin-API erreichbar =="
set +e
EXEC_OUT="$(compose exec -T "$CADDY_SERVICE" sh -ec '
probe() {
  url="$1"
  if command -v wget >/dev/null 2>&1; then
    wget -qO- -T 3 "$url" >/dev/null 2>&1
  elif command -v curl >/dev/null 2>&1; then
    curl --fail --silent --max-time 3 "$url" >/dev/null 2>&1
  else
    return 2
  fi
}

probe http://127.0.0.1:2019/config/ && exit 0
rc4=$?
probe http://[::1]:2019/config/ && exit 0
rc6=$?

if [ "$rc4" -eq 2 ] || [ "$rc6" -eq 2 ]; then
  exit 2
fi
exit 1
' </dev/null 2>&1)"
EXEC_RC=$?
set -e

if [[ $EXEC_RC -eq 2 ]]; then
  sysfail "no_http_client" \
    "Neither wget nor curl available inside the Caddy container"
elif [[ $EXEC_RC -ne 0 ]]; then
  fail "ADMIN_LOCAL_LOOPBACK" \
    "Admin API unreachable on IPv4 and IPv6 loopback (rc=$EXEC_RC)"
fi

echo "ADMIN_LOCAL_LOOPBACK=reachable"

echo "== B. Container-Listener-Bindung auf Port 2019 =="
set +e
PROC_TCP_OUT="$(compose exec -T "$CADDY_SERVICE" sh -c \
  'cat /proc/net/tcp 2>/dev/null; printf "\n---TCP6---\n"; cat /proc/net/tcp6 2>/dev/null' \
  </dev/null 2>&1)"
PROC_RC=$?
set -e
if [[ $PROC_RC -ne 0 ]]; then
  sysfail "proc_tcp" "Failed to read container socket table (rc=$PROC_RC)"
fi
[[ -n "$PROC_TCP_OUT" ]] || sysfail "proc_tcp_empty" "Empty socket table"

set +e
BINDING_RESULT="$(python3 - "$PROC_TCP_OUT" <<'PY'
import ipaddress
import socket
import sys

raw = sys.argv[1]
parts = raw.split("---TCP6---")
tcp4 = parts[0].splitlines()
tcp6 = parts[1].splitlines() if len(parts) > 1 else []
port_hex = format(2019, "04X")
checked = 0
violations = []


def ipv4(hex_ip: str) -> str:
    raw_ip = bytes.fromhex(hex_ip)
    return str(ipaddress.ip_address(raw_ip[::-1]))


def ipv6(hex_ip: str) -> str:
    raw_ip = bytes.fromhex(hex_ip)
    network = b"".join(raw_ip[i:i + 4][::-1] for i in range(0, 16, 4))
    return str(ipaddress.ip_address(socket.inet_ntop(socket.AF_INET6, network)))


for family, lines, decode, expected in (
    ("IPv4", tcp4, ipv4, "127.0.0.1"),
    ("IPv6", tcp6, ipv6, "::1"),
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
        if address != expected:
            violations.append(f"{family} non-loopback listener on {address}:2019")

if checked == 0:
    print("NO_LISTENER")
    sys.exit(2)
if violations:
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
print("loopback-only")
PY
)"
BINDING_RC=$?
set -e

if [[ "$BINDING_RESULT" == "NO_LISTENER" ]]; then
  fail "ADMIN_CONTAINER_NO_LISTENER" "No listener found on port 2019"
elif [[ $BINDING_RC -eq 1 ]]; then
  fail "ADMIN_CONTAINER_BINDING" "Port 2019 is bound to a non-loopback address"
elif [[ $BINDING_RC -ne 0 ]]; then
  sysfail "proc_parse" "Failed to parse container socket table"
fi

echo "ADMIN_CONTAINER_BINDING=loopback-only"

echo "== C. Compose veröffentlicht Port 2019 nicht =="
set +e
COMPOSE_JSON="$(compose config --format json 2>&1)"
COMPOSE_RC=$?
set -e
if [[ $COMPOSE_RC -ne 0 ]]; then
  sysfail "compose_config" "docker compose config failed (rc=$COMPOSE_RC)"
fi

set +e
python3 - "$COMPOSE_JSON" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    print(exc, file=sys.stderr)
    sys.exit(2)

ports = data.get("services", {}).get("caddy", {}).get("ports", [])
for entry in ports:
    if isinstance(entry, dict):
        published = entry.get("published")
        if published is not None and int(published) == 2019:
            sys.exit(1)
    elif isinstance(entry, str):
        if entry.split(":", 1)[0].strip() == "2019":
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
set +e
INSPECT_JSON="$(
  docker inspect "$CADDY_CONTAINER_ID" \
    --format '{{json .NetworkSettings.Ports}}' 2>&1
)"
INSPECT_RC=$?
set -e
if [[ $INSPECT_RC -ne 0 ]]; then
  sysfail "docker_inspect" \
    "docker inspect failed for $CADDY_CONTAINER_ID (rc=$INSPECT_RC)"
fi

set +e
python3 - "$INSPECT_JSON" <<'PY'
import json
import sys

try:
    ports = json.loads(sys.argv[1])
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
if command -v ss >/dev/null 2>&1; then
  set +e
  HOST_SOCKETS="$(ss -H -ltn 2>&1)"
  HOST_RC=$?
  set -e
elif command -v netstat >/dev/null 2>&1; then
  set +e
  HOST_SOCKETS="$(netstat -lnt 2>&1)"
  HOST_RC=$?
  set -e
else
  sysfail "no_ss_netstat" "Neither ss nor netstat is available"
fi
if [[ $HOST_RC -ne 0 ]]; then
  sysfail "host_socket_check" "Host listener inspection failed (rc=$HOST_RC)"
fi
if grep -Eq '(^|[[:space:]])([^[:space:]]*:)?2019([[:space:]]|$)' <<<"$HOST_SOCKETS"; then
  fail "ADMIN_HOST_LISTENER" "Host has a listener on port 2019"
fi

echo "ADMIN_HOST_LISTENER=absent"
echo "ADMIN_BOUNDARY_PROOF=PASS"
