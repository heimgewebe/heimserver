#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$REPO_ROOT/edge/docker-compose.yml.template"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cp "$TEMPLATE" "$TEST_DIR/docker-compose.yml"
touch "$TEST_DIR/Caddyfile"

compose_cmd=(
  docker compose
  --project-name edge
  --project-directory "$TEST_DIR"
  -f "$TEST_DIR/docker-compose.yml"
)

echo "== Edge Compose Contract =="

SERVICES="$("${compose_cmd[@]}" config --services)"

if [[ "$SERVICES" != "caddy" ]]; then
  echo "ERROR: Expected exactly the Compose service 'caddy'." >&2
  printf 'Observed services:\n%s\n' "$SERVICES" >&2
  exit 1
fi

RENDERED="$("${compose_cmd[@]}" config)"

require_rendered() {
  local expected="$1"

  if ! grep -Fq -- "$expected" <<< "$RENDERED"; then
    echo "ERROR: Missing rendered Compose contract: $expected" >&2
    printf '%s\n' "$RENDERED" >&2
    exit 1
  fi
}

reject_rendered() {
  local forbidden="$1"

  if grep -Fq -- "$forbidden" <<< "$RENDERED"; then
    echo "ERROR: Forbidden rendered Compose value: $forbidden" >&2
    printf '%s\n' "$RENDERED" >&2
    exit 1
  fi
}

require_rendered "container_name: edge-caddy"
require_rendered "source: caddy_data"
require_rendered "source: caddy_config"
require_rendered "name: edge_caddy_data"
require_rendered "name: edge_caddy_config"

reject_rendered "edge_edge_caddy_data"
reject_rendered "edge_edge_caddy_config"
reject_rendered "2019"

# Only 80 and 443 are published
PUBLISHED_PORTS="$(echo "$RENDERED" | awk '/published:/ {print $2}')"
for port in $PUBLISHED_PORTS; do
  port="${port//\"/}" # remove quotes if any
  if [[ "$port" != "80" && "$port" != "443" ]]; then
    echo "ERROR: Forbidden published port: $port" >&2
    exit 1
  fi
done

echo "PASS: Compose service ID is caddy"
echo "PASS: container name remains edge-caddy"
echo "PASS: deployed Caddy volume names are preserved"
echo "PASS: no doubled project prefix is rendered"
echo "PASS: Port 2019 is completely absent"
echo "PASS: Only 80 and 443 are published"
