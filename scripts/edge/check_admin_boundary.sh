#!/usr/bin/env bash
# check_admin_boundary.sh — Fail-closed Admin-API boundary guard
# Exit codes: 0=contract proven, 1=contract violated, 2=diagnosis not possible
set -uo pipefail

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
CADDY_CONTAINER="${CADDY_CONTAINER:-edge-caddy}"

fail() {
  echo "BOUNDARY VIOLATION ($1): $2" >&2
  exit 1
}

sysfail() {
  echo "DIAGNOSTIC FAILURE ($1): $2" >&2
  exit 2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    sysfail "missing_command" "Required command not found: $1"
  fi
}

require_cmd docker
require_cmd python3

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

# ── A. Containerlokale Admin-API erreichbar ───────────────────────────────────
echo "== A. Containerlokale Admin-API erreichbar =="

set +e
EXEC_OUT="$(compose exec -T "$CADDY_SERVICE" sh -ec '
  if command -v wget >/dev/null 2>&1; then
    wget -qO- http://127.0.0.1:2019/config/ >/dev/null 2>&1
    RC=$?
    if [ $RC -eq 0 ]; then exit 0; fi
    exit 1
  elif command -v curl >/dev/null 2>&1; then
    curl --fail --silent --max-time 3 http://127.0.0.1:2019/config/ >/dev/null 2>&1
    RC=$?
    if [ $RC -eq 0 ]; then exit 0; fi
    exit 1
  else
    exit 2
  fi
' </dev/null 2>&1)"
EXEC_RC=$?
set -e

if [[ $EXEC_RC -eq 2 ]]; then
  sysfail "no_http_client" "Neither wget nor curl available inside the Caddy container"
elif [[ $EXEC_RC -ne 0 ]] && compose ps --quiet "$CADDY_SERVICE" 2>/dev/null | grep -q .; then
  # Container is running but API not reachable → contract violation
  fail "ADMIN_LOCAL_LOOPBACK" "Admin API not reachable on 127.0.0.1:2019 inside container (exec_rc=$EXEC_RC)"
elif [[ $EXEC_RC -ne 0 ]]; then
  sysfail "compose_exec" "docker compose exec failed (rc=$EXEC_RC); container may not be running"
fi

echo "ADMIN_LOCAL_LOOPBACK=reachable"

# ── B. Tatsächliche Listener-Bindung via /proc/net/tcp im Container-Namespace ─
echo "== B. Container-Listener-Bindung auf Port 2019 =="

set +e
PROC_TCP_OUT="$(compose exec -T "$CADDY_SERVICE" sh -c \
  'cat /proc/net/tcp 2>/dev/null; printf "\n---TCP6---\n"; cat /proc/net/tcp6 2>/dev/null' \
  </dev/null 2>&1)"
PROC_RC=$?
set -e

if [[ $PROC_RC -ne 0 ]]; then
  sysfail "proc_tcp" "Failed to read /proc/net/tcp from container (rc=$PROC_RC)"
fi

if [[ -z "$PROC_TCP_OUT" ]]; then
  sysfail "proc_tcp_empty" "Empty /proc/net/tcp output from container"
fi

# Parse /proc/net/tcp(6) in Python — format:
#  tcp:  sl  local_address:port(hex)  remote_address  state  ...
#        state 0A = LISTEN
#  IPv4 local_address: HHHHHHHH:PPPP  (little-endian 4-byte hex IP, big-endian port)
#  IPv6 local_address: HHHH...32hex:PPPP
BINDING_RC=0
BINDING_RESULT="$(python3 - "$PROC_TCP_OUT" <<'PYEOF'
import sys, re

raw = sys.argv[1]
# Split into tcp4 and tcp6 sections
parts = raw.split("---TCP6---")
tcp4_lines = parts[0].strip().splitlines() if len(parts) > 0 else []
tcp6_lines = parts[1].strip().splitlines() if len(parts) > 1 else []

PORT_HEX = format(2019, '04X')  # '07E3'

violations = []
checked = 0

def ipv4_from_hex(hex_str):
    """Convert little-endian 4-byte hex IP to dotted notation."""
    val = int(hex_str, 16)
    b0 = val & 0xFF
    b1 = (val >> 8) & 0xFF
    b2 = (val >> 16) & 0xFF
    b3 = (val >> 24) & 0xFF
    return f"{b0}.{b1}.{b2}.{b3}"

def is_ipv4_loopback(hex_ip):
    ip = ipv4_from_hex(hex_ip)
    return ip == "127.0.0.1"

def ipv6_from_hex(hex_str):
    """Convert /proc/net/tcp6 hex address (32 chars, little-endian 4-byte groups) to colon notation."""
    # Each 8 chars = 4 bytes in little-endian
    groups = []
    for i in range(0, 32, 8):
        chunk = hex_str[i:i+8]
        val = int(chunk, 16)
        # reverse byte order
        b = [(val >> (8*j)) & 0xFF for j in range(4)]
        groups.append(f"{b[1]:02x}{b[0]:02x}")
        groups.append(f"{b[3]:02x}{b[2]:02x}")
    return ":".join(groups)

def is_ipv6_loopback(hex_ip):
    ip = ipv6_from_hex(hex_ip)
    # ::1 in full form
    return ip == "0000:0000:0000:0000:0000:0000:0000:0001"

# Parse tcp4
for line in tcp4_lines:
    line = line.strip()
    if not line or line.startswith("sl"):
        continue
    cols = line.split()
    if len(cols) < 4:
        continue
    local = cols[1]   # HHHHHHHH:PPPP
    state = cols[3]   # hex state
    if state != "0A":  # 0A = LISTEN
        continue
    parts2 = local.split(":")
    if len(parts2) != 2:
        continue
    hex_ip, hex_port = parts2
    if hex_port.upper() != PORT_HEX:
        continue
    checked += 1
    if not is_ipv4_loopback(hex_ip):
        ip = ipv4_from_hex(hex_ip)
        violations.append(f"IPv4 non-loopback listener on {ip}:2019")

# Parse tcp6
for line in tcp6_lines:
    line = line.strip()
    if not line or line.startswith("sl"):
        continue
    cols = line.split()
    if len(cols) < 4:
        continue
    local = cols[1]   # 32hex:PPPP
    state = cols[3]
    if state != "0A":
        continue
    parts2 = local.split(":")
    if len(parts2) != 2:
        continue
    hex_ip, hex_port = parts2
    if hex_port.upper() != PORT_HEX:
        continue
    checked += 1
    if not is_ipv6_loopback(hex_ip):
        ip = ipv6_from_hex(hex_ip)
        violations.append(f"IPv6 non-loopback listener on [{ip}]:2019")

if checked == 0:
    print("NO_LISTENER")
    sys.exit(2)

if violations:
    for v in violations:
        print(f"VIOLATION: {v}", file=sys.stderr)
    sys.exit(1)

print("loopback-only")
sys.exit(0)
PYEOF
)" || BINDING_RC=$?

if [[ "$BINDING_RESULT" == "NO_LISTENER" ]]; then
  sysfail "no_listener_2019" "No LISTEN socket found on port 2019 inside the container"
elif [[ $BINDING_RC -eq 1 ]]; then
  fail "ADMIN_CONTAINER_BINDING" "Port 2019 is bound to non-loopback address inside container"
elif [[ $BINDING_RC -eq 2 ]]; then
  sysfail "proc_parse" "Failed to parse container socket table"
elif [[ $BINDING_RC -ne 0 ]]; then
  sysfail "proc_parse_unknown" "Unexpected parser exit code: $BINDING_RC"
fi

echo "ADMIN_CONTAINER_BINDING=loopback-only"

# ── C. Compose veröffentlicht Port 2019 nicht ─────────────────────────────────
echo "== C. Compose veröffentlicht Port 2019 nicht =="

set +e
COMPOSE_JSON="$(compose config --format json 2>&1)"
COMPOSE_JSON_RC=$?
set -e

if [[ $COMPOSE_JSON_RC -ne 0 ]]; then
  sysfail "compose_config" "docker compose config --format json failed (rc=$COMPOSE_JSON_RC)"
fi

set +e
COMPOSE_CHECK="$(python3 - "$COMPOSE_JSON" <<'PYEOF'
import sys, json

raw = sys.argv[1]
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"JSON parse error: {e}", file=sys.stderr)
    sys.exit(2)

services = data.get("services", {})
caddy = services.get("caddy", {})
ports = caddy.get("ports", [])

for p in ports:
    published = None
    if isinstance(p, dict):
        published = p.get("published")
        target = p.get("target")
        # published may be int or string
        if published is not None and int(published) == 2019:
            print(f"VIOLATION: published port 2019 found (target={target})", file=sys.stderr)
            sys.exit(1)
    elif isinstance(p, str):
        # e.g. "80:80" or "2019:2019"
        parts = p.split(":")
        if parts[0].strip() == "2019":
            print(f"VIOLATION: published port 2019 in string format: {p}", file=sys.stderr)
            sys.exit(1)

print("absent")
sys.exit(0)
PYEOF
)"
COMPOSE_CHECK_RC=$?
set -e

if [[ $COMPOSE_CHECK_RC -eq 1 ]]; then
  fail "ADMIN_COMPOSE_PUBLISHED_PORT" "Port 2019 is published in Compose configuration"
elif [[ $COMPOSE_CHECK_RC -eq 2 ]]; then
  sysfail "compose_json_invalid" "Compose config JSON could not be parsed"
elif [[ $COMPOSE_CHECK_RC -ne 0 ]]; then
  sysfail "compose_check_unknown" "Unexpected compose check exit: $COMPOSE_CHECK_RC"
fi

echo "ADMIN_COMPOSE_PUBLISHED_PORT=absent"

# ── D. Laufender Container veröffentlicht Port 2019 nicht ────────────────────
echo "== D. Runtime-Container veröffentlicht Port 2019 nicht =="

set +e
INSPECT_JSON="$(docker inspect "$CADDY_CONTAINER" --format '{{json .NetworkSettings.Ports}}' 2>&1)"
INSPECT_RC=$?
set -e

if [[ $INSPECT_RC -ne 0 ]]; then
  sysfail "docker_inspect" "docker inspect failed for $CADDY_CONTAINER (rc=$INSPECT_RC)"
fi

set +e
INSPECT_CHECK="$(python3 - "$INSPECT_JSON" <<'PYEOF'
import sys, json

raw = sys.argv[1]
try:
    ports = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"JSON parse error: {e}", file=sys.stderr)
    sys.exit(2)

if ports is None:
    print("absent")
    sys.exit(0)

for key, bindings in ports.items():
    # key like "2019/tcp"
    proto_port = key.split("/")[0]
    try:
        if int(proto_port) == 2019 and bindings:
            print(f"VIOLATION: 2019/tcp is published: {bindings}", file=sys.stderr)
            sys.exit(1)
    except ValueError:
        pass

print("absent")
sys.exit(0)
PYEOF
)"
INSPECT_CHECK_RC=$?
set -e

if [[ $INSPECT_CHECK_RC -eq 1 ]]; then
  fail "ADMIN_RUNTIME_PUBLISHED_PORT" "Port 2019 is published in the running container"
elif [[ $INSPECT_CHECK_RC -eq 2 ]]; then
  sysfail "inspect_json_invalid" "docker inspect JSON could not be parsed"
elif [[ $INSPECT_CHECK_RC -ne 0 ]]; then
  sysfail "inspect_check_unknown" "Unexpected inspect check exit: $INSPECT_CHECK_RC"
fi

echo "ADMIN_RUNTIME_PUBLISHED_PORT=absent"

# ── E. Kein Hostlistener auf Port 2019 ───────────────────────────────────────
echo "== E. Kein Hostlistener auf Port 2019 =="

if command -v ss >/dev/null 2>&1; then
  set +e
  SS_OUT="$(ss -H -ltn 2>&1)"
  SS_RC=$?
  set -e
  if [[ $SS_RC -ne 0 ]]; then
    sysfail "ss_failed" "ss -H -ltn failed (rc=$SS_RC): $SS_OUT"
  fi
elif command -v netstat >/dev/null 2>&1; then
  set +e
  SS_OUT="$(netstat -lnt 2>&1)"
  SS_RC=$?
  set -e
  if [[ $SS_RC -ne 0 ]]; then
    sysfail "netstat_failed" "netstat -lnt failed (rc=$SS_RC): $SS_OUT"
  fi
else
  sysfail "no_ss_netstat" "Neither ss nor netstat available to check host listeners"
fi

# Any listener on port 2019 — including loopback — is a violation at host level
# /proc/net/tcp check above proves container-internal loopback is acceptable;
# a *host* listener on 2019 would mean the admin port escaped the container.
if echo "$SS_OUT" | grep -Eq '[[:space:]]([0-9]+\.){3}[0-9]+:2019[[:space:]]|[[].*]:2019[[:space:]]|\*:2019[[:space:]]|:2019[[:space:]]'; then
  fail "ADMIN_HOST_LISTENER" "Host has a listener on port 2019 — admin port must not escape the container"
fi

echo "ADMIN_HOST_LISTENER=absent"

# ── Final ─────────────────────────────────────────────────────────────────────
echo "ADMIN_BOUNDARY_PROOF=PASS"
exit 0
