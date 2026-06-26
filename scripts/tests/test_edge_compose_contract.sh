#!/usr/bin/env bash
# Compose contract test via validate_compose_contract.py.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/edge/docker-compose.yml.template"
VALIDATOR="$REPO_ROOT/scripts/edge/validate_compose_contract.py"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cp "$TEMPLATE" "$TEST_DIR/docker-compose.yml"
touch "$TEST_DIR/Caddyfile"
EXPECTED_CADDYFILE_SOURCE="${EXPECTED_CADDYFILE_SOURCE:-$TEST_DIR/Caddyfile}"

compose_cmd=(
  docker compose
  --project-name edge
  --project-directory "$TEST_DIR"
  -f "$TEST_DIR/docker-compose.yml"
)

echo "== Edge Compose Contract =="

COMPOSE_JSON_FILE="$TEST_DIR/compose_rendered.json"
COMPOSE_STDERR_FILE="$TEST_DIR/compose_rendered.stderr"
set +e
"${compose_cmd[@]}" config --format json \
  >"$COMPOSE_JSON_FILE" \
  2>"$COMPOSE_STDERR_FILE"
COMPOSE_JSON_RC=$?
set -e

if [[ $COMPOSE_JSON_RC -ne 0 ]]; then
  echo "ERROR: docker compose config --format json failed (rc=$COMPOSE_JSON_RC)" >&2
  cat "$COMPOSE_STDERR_FILE" >&2
  exit 2
fi

python3 - "$COMPOSE_JSON_FILE" <<'PY'
import json
import sys
from pathlib import Path

json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY

python3 "$VALIDATOR" \
  --service "$CADDY_SERVICE" \
  --expected-caddyfile-source "$EXPECTED_CADDYFILE_SOURCE" \
  --json "$COMPOSE_JSON_FILE"

echo "Compose stderr was captured separately:"
sed 's/^/  /' "$COMPOSE_STDERR_FILE"
echo "Edge Compose contract assertions passed"
