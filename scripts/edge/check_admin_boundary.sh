#!/usr/bin/env bash
set -euo pipefail

EDGE_DIR="${EDGE_DIR:-/opt/heimgewebe/edge}"
COMPOSE_FILE="${COMPOSE_FILE:-$EDGE_DIR/docker-compose.yml}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
CADDY_CONTAINER="${CADDY_CONTAINER:-edge-caddy}"
PROBE_IMAGE="${PROBE_IMAGE:-caddy:2.8.4}"

fail() {
  echo "ERROR ($1): $2" >&2
  exit 1
}

sysfail() {
  echo "DIAGNOSTIC ERROR ($1): $2" >&2
  exit 2
}

if ! command -v docker >/dev/null 2>&1; then
  sysfail "docker" "docker command not found"
fi

compose() {
  docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" "$@"
}

echo "== A. Containerlokale Admin-API erreichbar =="
if ! compose exec -T "$CADDY_SERVICE" sh -ec '
  if command -v wget >/dev/null 2>&1; then
    wget -qO- http://127.0.0.1:2019/config/ >/dev/null
  elif command -v curl >/dev/null 2>&1; then
    curl --fail --silent http://127.0.0.1:2019/config/ >/dev/null
  else
    exit 2
  fi
' < /dev/null; then
  fail "ADMIN_LOCAL_LOOPBACK" "Admin API not reachable on 127.0.0.1:2019 inside the container"
fi
echo "ADMIN_LOCAL_LOOPBACK=reachable"

echo "== B. Port 2019 nicht durch Compose veröffentlicht =="
# Check compose config
if compose config --format json 2>/dev/null | grep -q '"published":.*2019'; then
  fail "ADMIN_PUBLISHED_PORT" "Port 2019 is published in compose config"
fi

# Check docker inspect
if docker inspect "$CADDY_CONTAINER" --format '{{json .NetworkSettings.Ports}}' | grep -q '2019/tcp":\['; then
  fail "ADMIN_PUBLISHED_PORT" "Port 2019 is published in live container"
fi
echo "ADMIN_PUBLISHED_PORT=absent"

echo "== C. Kein Hostlistener auf Port 2019 =="
if command -v ss >/dev/null 2>&1; then
  if ss -lntp 2>/dev/null | grep -Eq '[:.]2019[[:space:]]'; then
    fail "ADMIN_HOST_LISTENER" "Host listener detected on port 2019"
  fi
elif command -v netstat >/dev/null 2>&1; then
  if netstat -lntp 2>/dev/null | grep -Eq '[:.]2019[[:space:]]'; then
    fail "ADMIN_HOST_LISTENER" "Host listener detected on port 2019"
  fi
else
  sysfail "ss/netstat" "Neither ss nor netstat is available to check host listeners"
fi
echo "ADMIN_HOST_LISTENER=absent"

echo "== D. Admin nicht über Container-IP erreichbar =="
if ! NETWORKS_JSON="$(docker inspect "$CADDY_CONTAINER" --format '{{json .NetworkSettings.Networks}}')"; then
  sysfail "docker_inspect" "Failed to inspect container networks"
fi

# We use jq if available, otherwise python to parse the networks and IPs
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  sysfail "jq/python3" "Neither jq nor python3 available to parse network config"
fi

parse_networks() {
  if command -v jq >/dev/null 2>&1; then
    echo "$NETWORKS_JSON" | jq -r 'to_entries | .[] | "\(.key) \(.value.IPAddress)"'
  else
    python3 -c "import sys, json; [print(f'{k} {v[\"IPAddress\"]}') for k, v in json.load(sys.stdin).items()]" <<< "$NETWORKS_JSON"
  fi
}

NETWORKS_PARSED="$(parse_networks)"
if [ -z "$NETWORKS_PARSED" ]; then
  sysfail "parse_networks" "No networks found or parsing failed"
fi

while read -r NET_NAME CONTAINER_IP; do
  if [ -z "$CONTAINER_IP" ]; then
    continue
  fi
  
  set +e
  docker run --rm --pull=never --network "$NET_NAME" "$PROBE_IMAGE" sh -ec '
    if command -v wget >/dev/null 2>&1; then
      wget -T 2 -qO- http://'"$CONTAINER_IP"':2019/config/ >/dev/null
    elif command -v curl >/dev/null 2>&1; then
      curl --fail --silent --connect-timeout 2 --max-time 3 http://'"$CONTAINER_IP"':2019/config/ >/dev/null
    else
      exit 2
    fi
  ' < /dev/null >/dev/null 2>&1
  probe_code=$?
  set -e

  if [ "$probe_code" -eq 0 ]; then
    fail "ADMIN_NETWORK_$NET_NAME" "Admin API is reachable over container network IP ($CONTAINER_IP)"
  elif [ "$probe_code" -eq 2 ] || [ "$probe_code" -ge 125 ]; then
    sysfail "probe" "Probe container failed to execute properly (exit code $probe_code)"
  fi
  echo "ADMIN_NETWORK_${NET_NAME}=unreachable"
done <<< "$NETWORKS_PARSED"

echo "ADMIN_BOUNDARY_PROOF=PASS"
exit 0
