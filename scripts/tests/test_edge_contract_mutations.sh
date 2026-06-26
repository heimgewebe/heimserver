#!/usr/bin/env bash
# Non-destructive structural mutation tests for Edge contracts.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATE="edge/Caddyfile.template"
CADDY_VALIDATOR="scripts/edge/validate_caddy_contract.py"
COMPOSE_VALIDATOR="scripts/edge/validate_compose_contract.py"
JSON_MUTATOR="scripts/tests/edge_contract_json_mutations.py"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8.4}"

PRE_SHA="$(find scripts/ edge/ runbooks/ -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}')"

MUTATION_DIR="$(mktemp -d)"
trap 'rm -rf "$MUTATION_DIR"' EXIT

FAILURES=0

run_caddyfile_case() {
  local desc="$1"
  local mutated_file="$2"
  local expected_rc="$3"
  local expected_stderr="${4:-}"
  local actual_rc=0 stderr_out

  stderr_out="$(python3 "$CADDY_VALIDATOR" --caddyfile "$mutated_file" 2>&1 >/dev/null)" || actual_rc=$?

  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    echo "FAIL [$desc]: expected rc $expected_rc, got $actual_rc"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -n "$expected_stderr" ]] && ! grep -qF -- "$expected_stderr" <<<"$stderr_out"; then
    echo "FAIL [$desc]: missing diagnostic $expected_stderr"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [$desc] rc=$actual_rc"
}

run_caddy_json_case() {
  local desc="$1"
  local mutation="$2"
  local expected_rc="$3"
  local expected_stderr="${4:-}"
  local mutated_json="$MUTATION_DIR/$mutation.json"
  local actual_rc=0 stderr_out

  python3 "$JSON_MUTATOR" \
    --source "$BASELINE_JSON" \
    --output "$mutated_json" \
    --mutation "$mutation"

  if cmp -s "$BASELINE_JSON" "$mutated_json"; then
    echo "FAIL [$desc]: mutation produced unchanged JSON"
    FAILURES=$((FAILURES + 1))
    return
  fi

  stderr_out="$(python3 "$CADDY_VALIDATOR" --adapted-json "$mutated_json" 2>&1 >/dev/null)" || actual_rc=$?
  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    echo "FAIL [$desc]: expected rc $expected_rc, got $actual_rc"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -n "$expected_stderr" ]] && ! grep -qF -- "$expected_stderr" <<<"$stderr_out"; then
    echo "FAIL [$desc]: missing diagnostic $expected_stderr"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [$desc] rc=$actual_rc"
}

run_caddy_json_document_case() {
  local desc="$1"
  local payload="$2"
  local expected_rc="$3"
  local expected_stderr="$4"
  local input="$MUTATION_DIR/caddy-document-${desc//[^a-zA-Z0-9]/-}.json"
  local actual_rc=0 stderr_out

  printf '%s\n' "$payload" >"$input"
  stderr_out="$(python3 "$CADDY_VALIDATOR" --adapted-json "$input" 2>&1 >/dev/null)" || actual_rc=$?

  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    echo "FAIL [$desc]: expected rc $expected_rc, got $actual_rc"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! grep -qF -- "$expected_stderr" <<<"$stderr_out"; then
    echo "FAIL [$desc]: missing diagnostic $expected_stderr"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if grep -qF -- "Traceback" <<<"$stderr_out"; then
    echo "FAIL [$desc]: leaked Python traceback"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [$desc] rc=$actual_rc"
}

run_caddy_timeout_case() {
  local value="$1"
  local actual_rc=0 stderr_out

  stderr_out="$(EDGE_SUBPROCESS_TIMEOUT_SECONDS="$value" python3 "$CADDY_VALIDATOR" --help 2>&1 >/dev/null)" || actual_rc=$?
  if [[ "$actual_rc" -ne 2 ]]; then
    echo "FAIL [timeout value $value]: expected rc 2, got $actual_rc"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! grep -qF -- "must be a positive integer" <<<"$stderr_out"; then
    echo "FAIL [timeout value $value]: missing controlled diagnostic"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if grep -qF -- "Traceback" <<<"$stderr_out"; then
    echo "FAIL [timeout value $value]: leaked Python traceback"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [timeout value $value rejected with rc=2]"
}

write_valid_compose_json() {
  local path="$1"
  cat >"$path" <<'JSON'
{
  "services": {
    "caddy": {
      "image": "caddy:2.8.4",
      "container_name": "edge-caddy",
      "ports": [
        {"published": 80, "target": 80, "protocol": "tcp"},
        {"published": 443, "target": 443, "protocol": "tcp"}
      ],
      "networks": {
        "edge": {},
        "heimnet": {},
        "weltgewebe_default": {}
      },
      "volumes": [
        {"type": "bind", "source": "/tmp/Caddyfile", "target": "/etc/caddy/Caddyfile", "read_only": true},
        {"type": "bind", "source": "/opt/weltgewebe/apps/web/build", "target": "/srv/weltgewebe-web", "read_only": true},
        {"type": "bind", "source": "/opt/weltgewebe/build/basemap", "target": "/srv/weltgewebe-basemap", "read_only": true},
        {"type": "bind", "source": "/opt/weltgewebe/map-style", "target": "/srv/weltgewebe-map-style", "read_only": true},
        {"type": "volume", "source": "caddy_data", "target": "/data"},
        {"type": "volume", "source": "caddy_config", "target": "/config"}
      ]
    }
  },
  "networks": {
    "edge": {"external": true},
    "heimnet": {"external": true},
    "weltgewebe_default": {"external": true}
  },
  "volumes": {
    "caddy_data": {"name": "edge_caddy_data"},
    "caddy_config": {"name": "edge_caddy_config"}
  }
}
JSON
}

mutate_compose_json() {
  local source="$1"
  local output="$2"
  local mutation="$3"
  python3 - "$source" "$output" "$mutation" <<'PY'
import json
import sys
from pathlib import Path

source, output, mutation = sys.argv[1:4]
data = json.loads(Path(source).read_text(encoding="utf-8"))
if mutation == "root-not-object":
    Path(output).write_text("[]\n", encoding="utf-8")
    raise SystemExit(0)

caddy = data["services"]["caddy"]


def remove_port(published):
    caddy["ports"] = [
        port
        for port in caddy["ports"]
        if int(port.get("published")) != published
    ]


def volume(target):
    for item in caddy["volumes"]:
        if item.get("target") == target:
            return item
    raise SystemExit(f"volume target not found: {target}")


if mutation == "port-80-missing":
    remove_port(80)
elif mutation == "port-443-missing":
    remove_port(443)
elif mutation == "port-2019-published":
    caddy["ports"].append({"published": 2019, "target": 2019, "protocol": "tcp"})
elif mutation == "network-mode-host":
    caddy["network_mode"] = "host"
elif mutation == "caddyfile-not-readonly":
    volume("/etc/caddy/Caddyfile")["read_only"] = False
elif mutation == "caddyfile-wrong-source":
    volume("/etc/caddy/Caddyfile")["source"] = "/tmp/unrelated-Caddyfile"
elif mutation == "web-build-not-readonly":
    volume("/srv/weltgewebe-web")["read_only"] = False
elif mutation == "web-build-wrong-source":
    volume("/srv/weltgewebe-web")["source"] = "/tmp/wrong-web-build"
elif mutation == "basemap-wrong-source":
    volume("/srv/weltgewebe-basemap")["source"] = "/tmp/wrong-basemap"
elif mutation == "map-style-wrong-source":
    volume("/srv/weltgewebe-map-style")["source"] = "/tmp/wrong-map-style"
elif mutation == "duplicate-web-target":
    caddy["volumes"].append(dict(volume("/srv/weltgewebe-web")))
elif mutation == "data-readonly":
    volume("/data")["read_only"] = True
elif mutation == "config-readonly":
    volume("/config")["read_only"] = True
elif mutation == "basemap-mount-missing":
    caddy["volumes"] = [
        item for item in caddy["volumes"]
        if item.get("target") != "/srv/weltgewebe-basemap"
    ]
elif mutation == "map-style-wrong-target":
    volume("/srv/weltgewebe-map-style")["target"] = "/srv/wrong-map-style"
elif mutation == "data-volume-declared-only":
    caddy["volumes"] = [
        item for item in caddy["volumes"]
        if item.get("target") != "/data"
    ]
elif mutation == "config-volume-wrong-target":
    volume("/config")["target"] = "/wrong-config"
elif mutation == "weltgewebe-network-missing":
    caddy["networks"].pop("weltgewebe_default")
elif mutation == "extra-service":
    data["services"]["sidecar"] = {"image": "busybox"}
else:
    raise SystemExit(f"unknown mutation: {mutation}")

Path(output).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_compose_case() {
  local desc="$1"
  local mutation="$2"
  local expected_rc="$3"
  local expected_stderr="${4:-}"
  local base="$MUTATION_DIR/compose-valid.json"
  local mutant="$MUTATION_DIR/compose-$mutation.json"
  local actual_rc=0 stderr_out

  write_valid_compose_json "$base"
  mutate_compose_json "$base" "$mutant" "$mutation"
  stderr_out="$(python3 "$COMPOSE_VALIDATOR" \
    --service caddy \
    --expected-caddyfile-source /tmp/Caddyfile \
    --json "$mutant" 2>&1 >/dev/null)" || actual_rc=$?

  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    echo "FAIL [$desc]: expected rc $expected_rc, got $actual_rc"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -n "$expected_stderr" ]] && ! grep -qF -- "$expected_stderr" <<<"$stderr_out"; then
    echo "FAIL [$desc]: missing diagnostic $expected_stderr"
    echo "$stderr_out"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [$desc] rc=$actual_rc"
}

echo "== Edge Contract Mutations =="

BASELINE="$MUTATION_DIR/Caddyfile.baseline"
cp "$TEMPLATE" "$BASELINE"
run_caddyfile_case "baseline Caddyfile" "$BASELINE" 0

BASELINE_JSON="$MUTATION_DIR/Caddyfile.baseline.json"
docker run \
  --rm \
  --pull=never \
  --network none \
  -v "$MUTATION_DIR:/candidate:ro" \
  "$CADDY_IMAGE" \
  caddy adapt \
    --adapter caddyfile \
    --config /candidate/Caddyfile.baseline \
  >"$BASELINE_JSON"

echo "-- Caddyfile mutants --"
M1="$MUTATION_DIR/admin-off.Caddyfile"
sed 's/admin 127.0.0.1:2019/admin off/' "$TEMPLATE" >"$M1"
run_caddyfile_case "admin off" "$M1" 1 "Admin is disabled"

M2="$MUTATION_DIR/admin-wildcard.Caddyfile"
sed 's/admin 127.0.0.1:2019/admin :2019/' "$TEMPLATE" >"$M2"
run_caddyfile_case "admin wildcard" "$M2" 1 "Admin listen address"

M3="$MUTATION_DIR/wrong-upstream.Caddyfile"
sed 's/weltgewebe-api:8080/wrong-api:9999/g' "$TEMPLATE" >"$M3"
run_caddyfile_case "wrong API upstream" "$M3" 1 "weltgewebe-api:8080"

M4="$MUTATION_DIR/wrong-basemap-root.Caddyfile"
sed 's|/srv/weltgewebe-basemap|/srv/wrong-basemap|g' "$TEMPLATE" >"$M4"
run_caddyfile_case "wrong basemap root" "$M4" 1 "PMTiles branch"

M5="$MUTATION_DIR/version-no-store-removed.Caddyfile"
sed '/Cache-Control.*no-store/d' "$TEMPLATE" >"$M5"
run_caddyfile_case "version no-store removed" "$M5" 1 "version metadata route"

echo "-- Caddy validator diagnostic inputs --"
run_caddy_json_document_case "JSON root array" "[]" 2 "root must be an object"
run_caddy_json_document_case "JSON root string" '"not-an-object"' 2 "root must be an object"
run_caddy_json_document_case "JSON root null" "null" 2 "root must be an object"
run_caddy_timeout_case "invalid"
run_caddy_timeout_case "0"
run_caddy_timeout_case "-1"

echo "-- Adapted Caddy JSON mutants --"
run_caddy_json_case "wrong redirect status" "redirect-status-wrong" 1 "Internal API redirect"
run_caddy_json_case "wrong redirect target" "redirect-target-wrong" 1 "Internal API redirect"
run_caddy_json_case "correct redirect on foreign host only" "redirect-foreign-host-decoy" 1 "Internal API redirect"
run_caddy_json_case "missing basemap route" "basemap-route-missing" 1 "basemap"
run_caddy_json_case "wrong basemap root" "basemap-root-wrong" 1 "PMTiles branch"
run_caddy_json_case "UI fallback before basemap" "fallback-before-basemap" 1 "Route ordering violation"
run_caddy_json_case "version no-store moved to fallback" "version-cache-misplaced" 1 "version metadata route"
run_caddy_json_case "version cache has conflicting value" "version-cache-conflicting" 1 "version metadata route"
run_caddy_json_case "immutable cache moved to fallback" "immutable-cache-misplaced" 1 "immutable route"
run_caddy_json_case "PMTiles CORS moved to fallback" "cors-misplaced" 1 "PMTiles branch"
run_caddy_json_case "PMTiles CORS has conflicting origin" "cors-conflicting" 1 "PMTiles branch"
run_caddy_json_case "OPTIONS 204 moved outside PMTiles" "options-misplaced" 1 "OPTIONS matcher and 204 response"
run_caddy_json_case "PMTiles file_server removed" "pmtiles-file-server-missing" 1 "root and file_server must coexist"
run_caddy_json_case "duplicate equal specific route" "duplicate-equal-specific-route" 1 "expected exactly one direct route"

echo "-- CADDY_IMAGE execution seam --"
MOCK_BIN="$MUTATION_DIR/mock-bin"
MOCK_DOCKER_LOG="$MUTATION_DIR/mock-docker.log"
mkdir -p "$MOCK_BIN"
cat >"$MOCK_BIN/docker" <<'MOCKDOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ "$1" == "image" && "$2" == "inspect" ]]; then
  [[ "$3" == "contract-test:caddy" ]] || exit 97
  exit 0
fi
if [[ "$1" == "run" ]]; then
  [[ " $* " == *" contract-test:caddy "* ]] || exit 98
  cat "$MOCK_ADAPTED_JSON"
  exit 0
fi
exit 99
MOCKDOCKER
chmod +x "$MOCK_BIN/docker"
export MOCK_DOCKER_LOG
export MOCK_ADAPTED_JSON="$BASELINE_JSON"
if PATH="$MOCK_BIN:$PATH" CADDY_IMAGE="contract-test:caddy" \
  python3 "$CADDY_VALIDATOR" --caddyfile "$BASELINE" >/dev/null 2>&1; then
  if grep -qF -- "image inspect contract-test:caddy" "$MOCK_DOCKER_LOG" \
    && grep -Eq '^run .* contract-test:caddy ' "$MOCK_DOCKER_LOG"; then
    echo "PASS [CADDY_IMAGE inspected and executed consistently]"
  else
    echo "FAIL [CADDY_IMAGE seam]: image mismatch"
    cat "$MOCK_DOCKER_LOG"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL [CADDY_IMAGE seam]: validator failed"
  cat "$MOCK_DOCKER_LOG"
  FAILURES=$((FAILURES + 1))
fi

echo "-- Compose mutants --"
VALID_COMPOSE="$MUTATION_DIR/compose-valid.json"
write_valid_compose_json "$VALID_COMPOSE"
if python3 "$COMPOSE_VALIDATOR" \
  --service caddy \
  --expected-caddyfile-source /tmp/Caddyfile \
  --json "$VALID_COMPOSE" >/dev/null; then
  echo "PASS [valid Compose contract]"
else
  echo "FAIL [valid Compose contract]"
  FAILURES=$((FAILURES + 1))
fi

run_compose_case "port 80 missing" "port-80-missing" 1 "Ports must be exactly"
run_compose_case "port 443 missing" "port-443-missing" 1 "Ports must be exactly"
run_compose_case "port 2019 published" "port-2019-published" 1 "Port 2019"
run_compose_case "network_mode host" "network-mode-host" 1 "network_mode: host"
run_compose_case "Caddyfile mount not read-only" "caddyfile-not-readonly" 1 "must be read-only"
run_compose_case "Caddyfile mount wrong source" "caddyfile-wrong-source" 1 "must use source"
run_compose_case "Web build mount not read-only" "web-build-not-readonly" 1 "must be read-only"
run_compose_case "Web build mount wrong source" "web-build-wrong-source" 1 "must use source"
run_compose_case "Basemap mount wrong source" "basemap-wrong-source" 1 "must use source"
run_compose_case "Map-style mount wrong source" "map-style-wrong-source" 1 "must use source"
run_compose_case "Duplicate Web mount target" "duplicate-web-target" 1 "Duplicate mount target"
run_compose_case "/data made read-only" "data-readonly" 1 "must remain writable"
run_compose_case "/config made read-only" "config-readonly" 1 "must remain writable"
run_compose_case "Basemap mount missing" "basemap-mount-missing" 1 "Missing required read-only mount"
run_compose_case "Map-style mount wrong target" "map-style-wrong-target" 1 "Missing required read-only mount"
run_compose_case "/data volume only declared" "data-volume-declared-only" 1 "Missing required volume mount"
run_compose_case "/config volume wrong target" "config-volume-wrong-target" 1 "Missing required volume mount"
run_compose_case "weltgewebe_default missing" "weltgewebe-network-missing" 1 "Missing service networks"
run_compose_case "unexpected extra service" "extra-service" 1 "Expected exactly 1 service"
run_compose_case "JSON root is not an object" "root-not-object" 2 "root must be an object"

echo "-- Runbook fail-closed command blocks --"
if python3 - "runbooks/edge.sync.md" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = re.findall(r"```bash\n(.*?)```", text, flags=re.DOTALL)
mutation_blocks = [
    block
    for block in blocks
    if "caddy reload" in block
    or "cat \"$1\" > \"$2\"" in block
]
if len(mutation_blocks) != 3:
    raise SystemExit(
        f"expected three manual reload/rollback mutation blocks, "
        f"found {len(mutation_blocks)}"
    )
for index, block in enumerate(mutation_blocks, start=1):
    if not block.lstrip().startswith("set -euo pipefail\n"):
        raise SystemExit(
            f"manual mutation block {index} lacks strict shell mode"
        )
PY
then
  echo "PASS [manual reload and rollback blocks fail closed]"
else
  echo "FAIL [manual reload and rollback blocks are not fail closed]"
  FAILURES=$((FAILURES + 1))
fi

echo "-- Post-Mutation Working Tree Integrity Check --"
POST_SHA="$(find scripts/ edge/ runbooks/ -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}')"
if [[ "$PRE_SHA" == "$POST_SHA" ]]; then
  echo "PASS [working tree unchanged by mutation tests]"
else
  echo "FAIL [working tree changed during mutation tests]"
  echo "pre=$PRE_SHA"
  echo "post=$POST_SHA"
  FAILURES=$((FAILURES + 1))
fi

if [[ $FAILURES -eq 0 ]]; then
  echo "== All mutation tests passed =="
else
  echo "== FAILED: $FAILURES contract mutation test(s) failed ==" >&2
  exit 1
fi
