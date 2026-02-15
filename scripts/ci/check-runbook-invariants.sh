#!/usr/bin/env bash
set -euo pipefail

# Invariant Check: Runbook consistency and naming policy

log() { printf "INFO: %s\n" "$*"; }
fail() { printf "FAIL: %s\n" "$*" >&2; exit 1; }

# 1. Check existence of example files (Template Safety)
if [ ! -f "infra/pihole/99-heimgewebe.conf.example" ]; then
  fail "Missing infra/pihole/99-heimgewebe.conf.example"
fi
if [ ! -f "infra/pihole/optional/99-weltgewebe.conf.example" ]; then
  fail "Missing infra/pihole/optional/99-weltgewebe.conf.example"
fi

# 2. Check absence of unmarked placeholders in Caddyfile (Drift Prevention)
# We expect Caddyfile.prod to be clean or commented out placeholders.
# We search for <.*> but exclude commented lines.
if grep -E "<.*>" infra/caddy/Caddyfile.prod | grep -vE "^[[:space:]]*#" >/dev/null; then
  fail "Active placeholder <...> found in infra/caddy/Caddyfile.prod"
fi

# 3. Check for unmarked placeholders in active pihole configs
# If any .conf file exists in infra/pihole/ (not .example), it must not contain placeholders.
if ls infra/pihole/*.conf >/dev/null 2>&1; then
  if grep -l "<.*>" infra/pihole/*.conf >/dev/null 2>&1; then
    fail "Found .conf file in infra/pihole/ containing placeholders. Rename to .example!"
  fi
fi

# 4. Check Canonical Naming Doc existence
if [ ! -f "docs/deploy/heimserver.naming.md" ]; then
  fail "Missing docs/deploy/heimserver.naming.md"
fi

# 5. Check Runbook Reference to Example Files
if ! grep -F "99-heimgewebe.conf.example" docs/runbooks/ops.runbook.leitstand-gateway.md >/dev/null; then
  fail "Runbook docs/runbooks/ops.runbook.leitstand-gateway.md does not reference 99-heimgewebe.conf.example"
fi
if ! grep -F "99-weltgewebe.conf.example" docs/runbooks/ops.runbook.leitstand-gateway.md >/dev/null; then
  fail "Runbook docs/runbooks/ops.runbook.leitstand-gateway.md does not reference 99-weltgewebe.conf.example"
fi

log "All invariants passed."
