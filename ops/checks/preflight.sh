#!/usr/bin/env bash
set -euo pipefail

# Preflight: minimale, robuste Checks zur Drift-Erkennung.
# Ziel: keine Abhängigkeiten außer Standard-Tools.

say() { printf "\n== %s ==\n" "$*"; }
ok()  { printf "OK: %s\n" "$*"; }
warn(){ printf "WARN: %s\n" "$*" >&2; }

say "host identity"
hostname || true
uname -a || true

say "interfaces (brief)"
ip -br link || true
ip -br addr || true

say "listeners (host)"
# Erwartung: keine Host-Listener auf 0.0.0.0:80/443
# Erwartung: kein Listener auf :2019 (Caddy admin)
if command -v ss >/dev/null 2>&1; then
  ss -lntup || true
  echo
  echo "Check: 80/443 listeners bound only to loopback?"
  non_loopback_listeners="$(ss -H -lntp | awk '{print $4}' | grep -E ':(80|443)$' | grep -Ev '^(127\.0\.0\.1|\[::1\]|::1):' || true)"
  if [ -n "${non_loopback_listeners:-}" ]; then
    warn "Non-loopback listeners on 80/443 detected (drift):"
    echo "$non_loopback_listeners" >&2
  else
    ok "Only loopback listeners on 80/443"
  fi

  echo "Check: Caddy admin :2019 listening?"
  if ss -lntup | grep -E ':(2019)\b' >/dev/null 2>&1; then
    warn "Listener on :2019 detected (drift)."
  else
    ok "No listener on :2019"
  fi
else
  warn "ss not available"
fi

say "docker publish (if docker is present)"
if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Ports}}' || true
else
  warn "docker not available"
fi

say "iptables (DOCKER-USER / policy)"
if command -v iptables >/dev/null 2>&1; then
  # DOCKER-USER chain rules
  sudo iptables -S DOCKER-USER || warn "Could not read DOCKER-USER (need sudo?)"
  echo
  echo "Check: DOCKER-USER contains allow LAN/WG + drop rest for 80/443?"
  # This is heuristic: looks for explicit allow rules to 80/443 for RFC1918 + WG and a drop for 80/443
  if sudo iptables -S DOCKER-USER 2>/dev/null | grep -E -- '--dport (80|443)' >/dev/null 2>&1; then
    ok "Found DOCKER-USER rules mentioning 80/443"
  else
    warn "No DOCKER-USER rules mentioning 80/443 found (verify manually)."
  fi
else
  warn "iptables not available"
fi

say "sysctl forwarding"
sysctl net.ipv4.ip_forward || true
sysctl net.ipv4.conf.all.rp_filter || true
sysctl net.ipv4.conf.default.rp_filter || true

say "wireguard"
if command -v wg >/dev/null 2>&1; then
  sudo wg show || warn "Could not read wg status (need sudo?)"
else
  warn "wg not available"
fi

say "dns quick check"
getent hosts heimserver || true

echo
echo "Done. If any WARN lines appeared, treat as drift until explained."
