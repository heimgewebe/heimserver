#!/usr/bin/env bash
# ops/audit/test_ipv6_detection.sh
# Tests the IPv6 listener detection logic used in ops/audit/collect.sh

set -euo pipefail

# Mock functions to capture the logic's reaction
gap_called=0
ok_called=0

gap() {
  echo "  (MOCK) GAP: $*"
  gap_called=1
}

ok() {
  echo "  (MOCK) OK: $*"
  ok_called=1
}

# The logic to test (Hardened version as implemented in ops/audit/collect.sh)
check_ipv6_listeners() {
  local ss_output="$1"
  gap_called=0
  ok_called=0

  # Replicates the hardened logic chain:
  # Uses tightened regex (numerical port required) to avoid false positives from peer columns (e.g. *:*)
  if printf '%s\n' "$ss_output" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\[::\]:[0-9]+$|^:::[0-9]+$|^\*:[0-9]+$/) print $i}' | grep -q .; then
    gap "IPv6 wildcard listeners detected. IPv6 may not be fully disabled or services bind dual-stack."
  else
    ok "No IPv6 wildcard listeners detected via ss."
  fi
}

# Test runner
run_test() {
  local name="$1"
  local input="$2"
  local expected_gap="$3"

  echo "Running test: $name"
  check_ipv6_listeners "$input"

  # Harden assertions: exactly one of ok/gap must be called
  if [ "$gap_called" -eq "$expected_gap" ] && [ "$ok_called" -eq "$((1 - expected_gap))" ]; then
    echo "  RESULT: SUCCESS"
  else
    echo "  RESULT: FAILURE (expected_gap=$expected_gap, gap_called=$gap_called, ok_called=$ok_called)"
    exit 1
  fi
  echo "-------------------------------------------------------------------------------"
}

echo "Starting IPv6 Listener Detection Tests"
echo "-------------------------------------------------------------------------------"

# Case 1: Only IPv4 listeners
run_test "IPv4 Only" \
"tcp LISTEN 0 128 0.0.0.0:80 0.0.0.0:*" \
0

# Case 2: IPv6 wildcard using [::]:port format (with Netid)
run_test "IPv6 Wildcard ([::]:port) with Netid" \
"tcp LISTEN 0 128 [::]:80 [::]:*" \
1

# Case 3: IPv6 wildcard using :::port format (with Netid)
run_test "IPv6 Wildcard (:::port) with Netid" \
"tcp LISTEN 0 128 :::80 :::*" \
1

# Case 4: IPv6 wildcard without Netid (e.g. ss -ltn)
run_test "IPv6 Wildcard without Netid" \
"LISTEN 0 128 [::]:80 [::]:*" \
1

# Case 5: IPv6 loopback only
run_test "IPv6 Loopback Only" \
"tcp LISTEN 0 128 [::1]:80 [::1]:*" \
0

# Case 6: Mixed IPv4 and IPv6
run_test "Mixed IPv4 and IPv6" \
"tcp LISTEN 0 128 0.0.0.0:443 0.0.0.0:*
tcp LISTEN 0 128 [::]:443 [::]:*" \
1

# Case 7: Ubuntu 24.04 '*' style for IPv6
run_test "IPv6 Wildcard (*:port)" \
"tcp LISTEN 0 128 *:80 *:*" \
1

# Case 8: False Positive Prevention (*:* in peer column)
# Even if *:port appears in peer column, it shouldn't trigger if it lacks a numeric port or isn't a wildcard bind
run_test "False Positive Prevention (*:* as peer)" \
"tcp LISTEN 0 128 127.0.0.1:80 *:*
tcp LISTEN 0 128 0.0.0.0:443 *:*" \
0

# Case 9: Service names (if ss is used without -n)
# Current logic expects numeric ports; if service names are used, it won't match.
# This is a documented limitation/choice for precision.
run_test "Service Names (should not match currently)" \
"tcp LISTEN 0 128 [::]:http [::]:*" \
0

echo "All IPv6 detection tests passed!"
