#!/usr/bin/env bash
set -euo pipefail

# Preflight: minimale, robuste Checks zur Drift-Erkennung.
# Ziel: keine Abhängigkeiten außer Standard-Tools.
#
# Architectural Decision:
# Services (Caddy, Docker Proxy) MAY listen on 0.0.0.0.
# Security is enforced via DOCKER-USER firewall rules, NOT by loopback binding.

LAN_SUBNET="${LAN_SUBNET:-192.168.178.0/24}"
WG_SUBNET="${WG_SUBNET:-10.7.0.0/24}"

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
# Erwartung: Listener auf 80/443 (Docker Proxy / Caddy)
# Erwartung: kein Listener auf :2019 (Caddy admin)
if command -v ss >/dev/null 2>&1; then
  ss -lntup || true
  echo
  echo "Check: 80/443 listeners present?"
  if ss -lntup | grep -E ':(80|443)\b' >/dev/null 2>&1; then
    ok "TCP Listeners on 80/443 found"
  else
    warn "No TCP listeners on 80/443 found (Caddy/Docker down?)"
  fi

  # Check UDP 443 (QUIC)
  if ss -lunp | grep -E ':443\b' >/dev/null 2>&1; then
      ok "UDP Listener on 443 found (QUIC active)"
  else
      warn "No UDP listener on 443 found (QUIC disabled or failed?)"
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
  # Guard logic: 80/443 must be explicitly allowed for LAN/WG and dropped for others.

  if ! sudo iptables -S DOCKER-USER >/dev/null 2>&1; then
      warn "Could not read DOCKER-USER (need sudo?)"
  else
      docker_user_rules="$(sudo iptables -S DOCKER-USER 2>/dev/null)"
      echo
      echo "Check: DOCKER-USER rules for 80/443 (Security Guard)?"

      if [ -z "$docker_user_rules" ]; then
          warn "DOCKER-USER chain empty or not found."
      else
          # LAN -> TCP 80 & 443
          if echo "$docker_user_rules" | grep -F -- "-s $LAN_SUBNET" | grep -F -- "--dport 80" | grep -q -- "-j ACCEPT"; then
              ok "LAN ($LAN_SUBNET) -> TCP 80 allowed"
          else
              warn "LAN ($LAN_SUBNET) -> TCP 80 allow rule missing"
          fi
          if echo "$docker_user_rules" | grep -F -- "-s $LAN_SUBNET" | grep -F -- "--dport 443" | grep -q -- "-j ACCEPT"; then
              ok "LAN ($LAN_SUBNET) -> TCP 443 allowed"
          else
              warn "LAN ($LAN_SUBNET) -> TCP 443 allow rule missing"
          fi

          # LAN -> UDP 443 (QUIC) - Optional but recommended if QUIC is active
          if echo "$docker_user_rules" | grep -F -- "-s $LAN_SUBNET" | grep -F -- "--dport 443" | grep -i "udp" | grep -q -- "-j ACCEPT"; then
              ok "LAN ($LAN_SUBNET) -> UDP 443 (QUIC) allowed"
          else
              warn "LAN ($LAN_SUBNET) -> UDP 443 (QUIC) allow rule missing (Check DOCKER-USER)"
          fi

          # WireGuard -> TCP 80 & 443
          if echo "$docker_user_rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "--dport 80" | grep -q -- "-j ACCEPT"; then
              ok "WG ($WG_SUBNET) -> TCP 80 allowed"
          else
              warn "WG ($WG_SUBNET) -> TCP 80 allow rule missing"
          fi
          if echo "$docker_user_rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "--dport 443" | grep -q -- "-j ACCEPT"; then
              ok "WG ($WG_SUBNET) -> TCP 443 allowed"
          else
              warn "WG ($WG_SUBNET) -> TCP 443 allow rule missing"
          fi

          # WireGuard -> UDP 443 (QUIC)
          if echo "$docker_user_rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "--dport 443" | grep -i "udp" | grep -q -- "-j ACCEPT"; then
              ok "WG ($WG_SUBNET) -> UDP 443 (QUIC) allowed"
          else
              warn "WG ($WG_SUBNET) -> UDP 443 (QUIC) allow rule missing"
          fi

          # Drop Rest Logic
          if echo "$docker_user_rules" | grep -E -q -- "-j (DROP|RETURN|REJECT)"; then
              ok "Drop/Return/Reject policy found (heuristic)"
          else
              warn "No explicit Drop/Return policy found (verify manually: sudo iptables -S DOCKER-USER)"
          fi
      fi
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
