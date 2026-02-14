#!/usr/bin/env bash
set -euo pipefail

# Audit-Kollektor
# Ziel: Operativen Status festhalten, OHNE Secrets zu leaken.
# Speicherort: ops/audit/snapshots/<YYYY-MM-DD-HHMM>/

TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
SNAPSHOT_DIR="ops/audit/snapshots/$TIMESTAMP"
SUMMARY_FILE="$SNAPSHOT_DIR/SUMMARY.md"

mkdir -p "$SNAPSHOT_DIR"

say() { echo "  > $*"; }
log_cmd() {
  local cmd="$1"
  local file="$2"
  say "Running $cmd -> $file"
  echo "== $cmd ==" > "$SNAPSHOT_DIR/$file"
  if eval "$cmd" >> "$SNAPSHOT_DIR/$file" 2>&1; then
    return 0
  else
    echo "(Command failed or not available)" >> "$SNAPSHOT_DIR/$file"
    # Return 0 so set -e doesn't kill the script; we logged the failure.
    return 0
  fi
}

echo "Starting Audit Collection for $TIMESTAMP..."

# 1. Docker Status (Safe)
log_cmd "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}'" "docker_ps.txt"
log_cmd "docker network ls" "docker_networks.txt"

# 2. Host Listeners (Safe-ish - Ports only)
log_cmd "ss -lntup" "ss_lntup.txt"

# 2b. Caddy Internal Status
log_cmd "docker exec edge-caddy caddy version" "caddy_version.txt"
log_cmd "docker exec edge-caddy caddy validate --config /etc/caddy/Caddyfile" "caddy_validate.txt"

# Check if ss is available inside the container (without crashing script)
if docker exec edge-caddy command -v ss >/dev/null 2>&1; then
    log_cmd "docker exec edge-caddy ss -lntup" "caddy_container_ss.txt"
else
    echo "GAP: ss not available in caddy container (or container down)" > "$SNAPSHOT_DIR/caddy_ss_missing.txt"
fi

# 2c. Kernel / Sysctl Status
log_cmd "sysctl net.ipv4.ip_forward" "sysctl_ip_forward.txt"
log_cmd "sysctl net.ipv4.conf.all.rp_filter" "sysctl_rp_filter.txt"

# 3. Firewall Rules (CRITICAL - DOCKER-USER Guard)
if command -v iptables >/dev/null; then
  log_cmd "sudo iptables -S DOCKER-USER" "iptables_docker_user.txt"
  log_cmd "sudo iptables -t nat -S POSTROUTING" "iptables_nat.txt"
else
  echo "GAP: iptables not available" > "$SNAPSHOT_DIR/iptables_missing.txt"
fi

# 4. WireGuard Status (SANITIZED)
# wg show output contains IPs but NO keys in default output (public keys are ok, private hidden)
# We grep to ensure no "private key" lines leak just in case.
if command -v wg >/dev/null; then
  say "Running wg show (sanitized)"
  echo "== sudo wg show ==" > "$SNAPSHOT_DIR/wg_show.txt"
  # Sanitization: remove private keys AND endpoints (IPs)
  sudo wg show | grep -vE "private key|endpoint:" >> "$SNAPSHOT_DIR/wg_show.txt" 2>&1 || true
else
  echo "GAP: wg not available" > "$SNAPSHOT_DIR/wg_missing.txt"
fi

# 5. DNS Resolution Check
log_cmd "dig +short leitstand.heimgewebe.home.arpa @127.0.0.1" "dns_dig_fqdn.txt"
log_cmd "getent hosts leitstand.heimgewebe.home.arpa" "dns_getent_fqdn.txt"
log_cmd "getent hosts leitstand" "dns_getent_short.txt"

# 6. Generate Summary
cat <<EOF > "$SUMMARY_FILE"
# Audit Snapshot $TIMESTAMP

**Host:** $(hostname)
**Date:** $(date)

## Captured Artifacts
- [x] Docker Containers & Networks
- [x] Host Listeners (ss)
- [x] Caddy Internals (Version, Validate)
- [x] Kernel Sysctl (Forwarding, RP Filter)
- [ ] Firewall Rules (iptables) - $([ -f "$SNAPSHOT_DIR/iptables_docker_user.txt" ] && echo "OK" || echo "MISSING")
- [ ] WireGuard Status - $([ -f "$SNAPSHOT_DIR/wg_show.txt" ] && echo "OK" || echo "MISSING")
- [ ] DNS Check - $([ -f "$SNAPSHOT_DIR/dns_dig_fqdn.txt" ] && echo "OK" || echo "MISSING")

## Gaps / Errors
$(grep -r "GAP:" "$SNAPSHOT_DIR" || echo "None detected.")

## Notes
- This snapshot is git-ignored by default.
- Review contents before sharing (Redaction required!).
- Snapshot contains REAL IPs/Subnets.
- NO PRIVATE KEYS should be present.
- 'wg_show.txt' is sanitized but may contain residual metadata.
EOF

echo "Audit complete. Snapshot saved to: $SNAPSHOT_DIR"
