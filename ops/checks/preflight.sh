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
ALLOW_QUIC="${ALLOW_QUIC:-0}"

say() { printf "\n== %s ==\n" "$*"; }
ok()  { printf "PASS (heuristic): %s\n" "$*"; }
warn(){ printf "WARN (manual verify): %s\n" "$*" >&2; }

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
      if [ "${ALLOW_QUIC}" = "1" ]; then
          ok "UDP 443 listener present (QUIC allowed)"
      else
          warn "UDP 443 listener present (QUIC/HTTP3 active). Set ALLOW_QUIC=1 if intentional."
      fi
  else
      if [ "${ALLOW_QUIC}" = "1" ]; then
          warn "QUIC allowed but no UDP 443 listener found."
      else
          ok "No UDP 443 listener (QUIC disabled)"
      fi
  fi

  echo "Check: Caddy admin :2019 host-exposed?"
  if ss -lntup | grep -E ':(2019)\b' >/dev/null 2>&1; then
    warn "Host listener on :2019 detected (drift). Admin port exposed?"
  else
    ok "No host listener on :2019"
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
      # Always print DOCKER-USER rules for visibility
      echo "--- DOCKER-USER Rules ---"
      echo "$docker_user_rules"
      echo "-------------------------"

      echo
      echo "Check: DOCKER-USER rules for 80/443 (Security Guard)?"

      if [ -z "$docker_user_rules" ]; then
          warn "DOCKER-USER chain empty or not found."
      else
          # Heuristic: Scan for ACCEPT rules covering subnets + ports (tolerant match)
          # We search for lines containing subnet AND port AND ACCEPT.

          # LAN
          if echo "$docker_user_rules" | grep -F -- "-s $LAN_SUBNET" | grep -E -- "(80|443|http|https)" | grep -q -- "-j ACCEPT"; then
              ok "LAN ($LAN_SUBNET) -> HTTP/HTTPS allowed (heuristic)"
          else
              warn "LAN ($LAN_SUBNET) allow rule not confident. MANUAL REVIEW REQUIRED."
          fi

          # WireGuard
          if echo "$docker_user_rules" | grep -F -- "-s $WG_SUBNET" | grep -E -- "(80|443|http|https)" | grep -q -- "-j ACCEPT"; then
              ok "WG ($WG_SUBNET) -> HTTP/HTTPS allowed (heuristic)"
          else
              warn "WG ($WG_SUBNET) allow rule not confident. MANUAL REVIEW REQUIRED."
          fi

          # UDP 443 (QUIC) checks if enabled
          if [ "${ALLOW_QUIC}" = "1" ]; then
              if echo "$docker_user_rules" | grep -i "udp" | grep -E -- "(--dport 443|multiport.*443)" | grep -q -- "-j ACCEPT"; then
                   ok "UDP 443 allow rule found (heuristic)"
              else
                   warn "UDP 443 allow rule missing/unverified (Check DOCKER-USER)"
              fi
          fi

          # Drop Rest Logic: Any Drop/Reject for 80/443 OR generic catch-all
          if echo "$docker_user_rules" | grep -E -- "(80|443)" | grep -E -q -- "-j (DROP|REJECT)"; then
              ok "Explicit Drop/Reject rule for 80/443 found (heuristic)"
          elif echo "$docker_user_rules" | grep -E -q -- "-j (DROP|RETURN|REJECT)$"; then
              ok "Generic Drop/Return/Reject policy found (heuristic)"
          else
              warn "No explicit Drop/Return policy found (verify manually)"
          fi
      fi

      echo "Authoritative review: sudo iptables -S DOCKER-USER"
      echo "Authoritative review: sudo iptables -L DOCKER-USER -n -v"
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
