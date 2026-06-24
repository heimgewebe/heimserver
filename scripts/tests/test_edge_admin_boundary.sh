#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../edge/check_admin_boundary.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export PATH="$TEST_DIR/bin:$PATH"
mkdir -p "$TEST_DIR/bin"

cat << 'MOCK' > "$TEST_DIR/bin/docker"
#!/usr/bin/env bash
CMD="$1"
shift

if [[ "$CMD" == "compose" ]]; then
  if [[ "$*" == *"exec -T caddy sh -ec"* ]]; then
    if [[ "${MOCK_EXEC_FAIL:-0}" == "1" ]]; then exit 1; fi
    exit 0
  fi
  if [[ "$*" == *"config --format json"* ]]; then
    if [[ "${MOCK_COMPOSE_PUBLISH:-0}" == "1" ]]; then
      echo '{"published": 2019}'
    else
      echo '{}'
    fi
    exit 0
  fi
elif [[ "$CMD" == "inspect" ]]; then
  if [[ "$1" == "edge-caddy" ]]; then
    if [[ "$*" == *".NetworkSettings.Ports"* ]]; then
      if [[ "${MOCK_INSPECT_PUBLISH:-0}" == "1" ]]; then
        echo '{"2019/tcp":[{"HostIp":"0.0.0.0","HostPort":"2019"}]}'
      else
        echo '{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"80"}]}'
      fi
      exit 0
    elif [[ "$*" == *".NetworkSettings.Networks"* ]]; then
      if [[ "${MOCK_INSPECT_NO_NET:-0}" == "1" ]]; then
        echo '{}'
      else
        echo '{"edge":{"IPAddress":"172.20.0.2"}}'
      fi
      exit 0
    fi
  fi
elif [[ "$CMD" == "run" ]]; then
  if [[ "$*" != *"--rm"* ]] || [[ "$*" != *"--pull=never"* ]]; then
    echo "ERROR: Probe container arguments are invalid." >&2
    exit 2
  fi
  if [[ "${MOCK_IMAGE_MISSING:-0}" == "1" ]]; then
    echo "Error: image missing" >&2
    exit 125
  fi
  if [[ "${MOCK_PROBE_SUCCESS:-0}" == "1" ]]; then
    exit 0
  else
    exit 1
  fi
fi
exit 1
MOCK
chmod +x "$TEST_DIR/bin/docker"

cat << 'MOCK' > "$TEST_DIR/bin/ss"
#!/usr/bin/env bash
if [[ "${MOCK_SS_LISTENER:-none}" == "127.0.0.1" ]]; then
  echo "LISTEN 0 128 127.0.0.1:2019 0.0.0.0:*"
elif [[ "${MOCK_SS_LISTENER:-none}" == "0.0.0.0" ]]; then
  echo "LISTEN 0 128 0.0.0.0:2019 0.0.0.0:*"
else
  echo "LISTEN 0 128 0.0.0.0:80 0.0.0.0:*"
fi
MOCK
chmod +x "$TEST_DIR/bin/ss"

run_test() {
  local msg="$1"
  local exp_code="$2"
  local env_var="$3"

  echo "Testing: $msg"
  local out
  local code=0
  out="$(eval "$env_var bash \"$GUARD_SCRIPT\"" 2>&1)" || code=$?

  if [[ "$code" != "$exp_code" ]]; then
    echo "  FAIL: Expected exit $exp_code, got $code"
    echo "  Output:"
    echo "$out"
    exit 1
  fi
  echo "  PASS: Exit $code"
}

run_test "1. sicherer Zustand" 0 ""
run_test "2. lokale Admin-API nicht erreichbar" 1 "MOCK_EXEC_FAIL=1"
run_test "3. Compose veröffentlicht 2019" 1 "MOCK_COMPOSE_PUBLISH=1"
run_test "4. docker inspect veröffentlichten 2019-Port" 1 "MOCK_INSPECT_PUBLISH=1"
run_test "5. Hostlistener 127.0.0.1:2019" 1 "MOCK_SS_LISTENER=127.0.0.1"
run_test "6. Hostlistener 0.0.0.0:2019" 1 "MOCK_SS_LISTENER=0.0.0.0"
run_test "7. Probecontainer erreicht Admin" 1 "MOCK_PROBE_SUCCESS=1"
run_test "9. fehlendes gemeinsames Netzwerk" 2 "MOCK_INSPECT_NO_NET=1"
run_test "10. fehlendes Probeimage" 2 "MOCK_IMAGE_MISSING=1"

echo "ALL ADMIN BOUNDARY TESTS PASSED"
