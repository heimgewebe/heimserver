#!/usr/bin/env bash
# test_edge_compose_contract.sh — Compose contract test via validate_compose_contract.py
# Uses docker compose config --format json to get rendered JSON, then validates it.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/edge/docker-compose.yml.template"
VALIDATOR="$REPO_ROOT/scripts/edge/validate_compose_contract.py"

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

# Step 1: Get rendered JSON (capture exit code separately)
COMPOSE_JSON_FILE="$TEST_DIR/compose_rendered.json"
set +e
"${compose_cmd[@]}" config --format json > "$COMPOSE_JSON_FILE" 2>&1
COMPOSE_JSON_RC=$?
set -e

if [[ $COMPOSE_JSON_RC -ne 0 ]]; then
    echo "ERROR: docker compose config --format json failed (rc=$COMPOSE_JSON_RC)" >&2
    cat "$COMPOSE_JSON_FILE" >&2
    exit 2
fi

# Step 2: Run structural validator
set +e
python3 "$VALIDATOR" --json "$COMPOSE_JSON_FILE"
VALIDATOR_RC=$?
set -e

if [[ $VALIDATOR_RC -ne 0 ]]; then
    echo "ERROR: validate_compose_contract.py failed (rc=$VALIDATOR_RC)" >&2
    exit "$VALIDATOR_RC"
fi

# Step 3: Validate the exact internal API redirect target independently.
bash "$SCRIPT_DIR/test_edge_redirect_target.sh"

echo "✅ All Compose and redirect contract assertions passed"
