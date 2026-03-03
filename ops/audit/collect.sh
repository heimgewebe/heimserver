#!/usr/bin/env bash
set -euo pipefail

# ops/audit/collect.sh
# Ziel: Operativen Status festhalten, OHNE Secrets zu leaken.
# Speicherort: ops/audit/snapshots/<YYYY-MM-DD-HHMM>/
#
# Sicherheitsprinzip:
# - Keine Private Keys / Secrets sammeln.
# - WG Output wird zusätzlich gesäubert.
# - Review vor dem Teilen.

TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
SNAPSHOT_DIR="ops/audit/snapshots/${TIMESTAMP}"
mkdir -p "$SNAPSHOT_DIR"

# Config (optional überschreibbar)
LAN_SUBNET="${LAN_SUBNET:-192.168.178.0/24}"
WG_SUBNET="${WG_SUBNET:-10.7.0.0/24}"
EXPECTED_WG_IF="${EXPECTED_WG_IF:-wg0}"
EXPECTED_LAN_IF="${EXPECTED_LAN_IF:-eno2}"

say() { printf "\n== %s ==\n" "$*"; }
note(){ printf "NOTE: %s\n" "$*"; }
gap() { printf "GAP: %s\n" "$*" | tee -a "$SNAPSHOT_DIR/GAPS.txt" >&2; }
ok()  { printf "OK: %s\n" "$*"; }

run() {
  local label="$1"; shift
  local file="$1"; shift
  say "$label"
  {
    echo "== $label =="
    echo "CMD: $*"
    echo "DATE: $(date -Is)"
    echo
    # Initialize rc to 0 to avoid unbound variable issues if not set
    local rc=0
    # Capture command output and exit code
    if "$@" 2>&1; then
      :
    else
      rc=$?
      echo
      echo "(command failed, RC=$rc)"
    fi
  } > "$SNAPSHOT_DIR/$file"
}

have() { command -v "$1" >/dev/null 2>&1; }

echo "Starting Audit Collection: $TIMESTAMP" | tee "$SNAPSHOT_DIR/START.txt"

###############################################################################
# Q1: IPv6 wirklich deaktiviert? (Host + Listener + Docker)
###############################################################################
say "Q1: IPv6 disabled?"
if have sysctl; then
  run "sysctl ipv6 disable flags" "ipv6_sysctl.txt" \
    sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6
else
  gap "sysctl not available; cannot verify IPv6 disable flags."
fi

if have ss; then
  # Listener check: if IPv6 disabled, ideally no :::80/:::443 etc.
  run "host listeners (ss -lntup)" "listeners_ss_lntup.txt" ss -lntup
  # Robust check for IPv6 wildcard listeners (handles different ss output formats)
  if ss -H -lntup | awk '{for(i=1;i<=NF;i++) if($i ~ /^\[::\]:|^:::|^\*:/) print $i}' | grep -q .; then
    gap "IPv6 wildcard listeners detected. IPv6 may not be fully disabled or services bind dual-stack."
  else
    ok "No IPv6 wildcard listeners detected via ss."
  fi
else
  gap "ss not available; cannot verify listeners."
fi

if have docker; then
  run "docker info (network/iptables hints)" "docker_info.txt" docker info
  # Docker daemon IPv6 setting if present
  if docker info 2>/dev/null | grep -qi 'IPv6: *true'; then
    gap "Docker reports IPv6=true (verify daemon.json and network settings)."
  else
    ok "Docker does not report IPv6=true (not definitive, but good sign)."
  fi
else
  gap "docker not available; cannot verify docker ipv6/iptables behaviour."
fi

###############################################################################
# Q2: Firewall backend consistency (iptables-nft vs nft)
###############################################################################
say "Q2: Firewall backend consistency (iptables-nft vs nft)"
if have iptables; then
  run "iptables version" "iptables_version.txt" iptables --version
else
  gap "iptables not available."
fi

if have nft; then
  # nft list can be large; still useful for truth-source when debugging.
  run "nft list ruleset (full)" "nft_ruleset.txt" sudo nft list ruleset
else
  gap "nft not available (cannot directly inspect nft ruleset)."
fi

###############################################################################
# Q3: DOCKER-USER Guard wirksam?
###############################################################################
say "Q3: DOCKER-USER guard present & plausible?"
if have iptables; then
  run "iptables DOCKER-USER (authoritative)" "iptables_docker_user_S.txt" sudo iptables -S DOCKER-USER
  run "iptables DOCKER-USER (counters)" "iptables_docker_user_L.txt" sudo iptables -L DOCKER-USER -n -v --line-numbers

  # Heuristic assertions: allow LAN/WG to 80/443; drop others for 80/443.
  rules="$(sudo iptables -S DOCKER-USER 2>/dev/null || true)"

  # ACCEPT LAN -> tcp dport 80 or 443 (including multiport)
  # Updated logic: Robust chained grep + port boundaries
  # Matches: -s LAN ... -p tcp ... --dport 80/443 ... -j ACCEPT
  # Order-agnostic, subnet literal, precise ports (no 8080)
  if echo "$rules" | grep -F -- "-s $LAN_SUBNET" | grep -F -- "-p tcp" | grep -qE -- "(-m multiport --dports (80,443|443,80)([^0-9]|$)|--dport (80|443)([^0-9]|$)).*-j ACCEPT"; then
    ok "Found LAN allow rule for tcp 80/443 (heuristic)."
  else
    gap "LAN allow rule for tcp 80/443 not confidently found. Manual review required."
  fi

  if echo "$rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "-p tcp" | grep -qE -- "(-m multiport --dports (80,443|443,80)([^0-9]|$)|--dport (80|443)([^0-9]|$)).*-j ACCEPT"; then
    ok "Found WG allow rule for tcp 80/443 (heuristic)."
  else
    gap "WG allow rule for tcp 80/443 not confidently found. Manual review required."
  fi

  # DROP/REJECT for tcp 80/443 from others
  # Using grep -qE to avoid printing matched lines
  if echo "$rules" | grep -F -- "-p tcp" | grep -qE -- "(-m multiport --dports (80,443|443,80)([^0-9]|$)|--dport (80|443)([^0-9]|$)).*-j (DROP|REJECT)"; then
    ok "Found explicit DROP/REJECT for tcp 80/443 (heuristic)."
  else
    gap "No explicit DROP/REJECT for tcp 80/443 found (heuristic). Ensure default path is safe."
  fi
else
  gap "iptables missing; cannot validate DOCKER-USER guard."
fi

###############################################################################
# Q4: UFW/Firewalld Konflikte
###############################################################################
say "Q4: Firewall managers conflicting?"
if have ufw; then
  run "ufw status verbose" "ufw_status.txt" sudo ufw status verbose
else
  note "ufw not installed (ok if intentional)."
fi

if have systemctl; then
  # Use subshell to isolate rc_fw variable
  (
    # Simplified robust check using exit codes
    # 4 = not found, 0 = active, 3 = inactive (usually)
    rc_fw=0
    set +e
    systemctl status firewalld.service >/dev/null 2>&1
    rc_fw=$?
    set -e

    if [ "$rc_fw" -eq 4 ]; then
      ok "firewalld not installed (service unit not found)."
    elif [ "$rc_fw" -eq 0 ]; then
      gap "firewalld is active. Potential conflict with docker iptables."
      run "firewalld status" "firewalld_status.txt" systemctl status firewalld
    elif [ "$rc_fw" -eq 3 ]; then
      ok "firewalld installed but not active."
      run "firewalld enabled state" "firewalld_enabled.txt" systemctl is-enabled firewalld
    else
      # Fallback for unexpected return codes
      note "firewalld status returned unexpected RC=$rc_fw; logging status output"
      run "firewalld status (raw)" "firewalld_status_raw.txt" systemctl status firewalld.service
    fi
  )
else
  gap "systemctl not available; cannot check firewalld."
fi

###############################################################################
# Q5: Port exposure review (host + docker + caddy internal)
###############################################################################
say "Q5: Port exposure review (host + docker)"
if have ss; then
  run "listeners tcp/udp important ports" "listeners_filtered.txt" \
    bash -c "ss -lntup; echo; ss -lunp"
  # QUIC/UDP 443
  if ss -lunp | grep -qE ':(443)\b'; then
    gap "UDP 443 listener detected (QUIC/HTTP3 may be active). Verify intentionality."
  else
    ok "No UDP 443 listener detected."
  fi

  # Caddy admin port host exposure
  if ss -lntup | grep -qE ':(2019)\b'; then
    gap "Host listener on 2019 detected (Caddy admin exposure risk)."
  else
    ok "No host listener on 2019 detected."
  fi
else
  gap "ss missing; cannot check port exposure."
fi

if have docker; then
  # Use subshell to isolate rc/running variables
  (
    run "docker ps ports view" "docker_ps_ports.txt" \
      docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    run "docker network ls" "docker_networks.txt" docker network ls

    # Internal Caddy Checks
    say "Internal Caddy Checks"

    # Verify edge-caddy is running before exec
    rc=0
    set +e
    docker inspect -f '{{.State.Running}}' edge-caddy >/dev/null 2>&1
    rc=$?
    set -e

    if [ "$rc" -ne 0 ]; then
        note "edge-caddy container not found; skipping internal checks."
    else
        running=$(docker inspect -f '{{.State.Running}}' edge-caddy)
        if [ "$running" != "true" ]; then
            note "edge-caddy not running; skipping internal checks."
        else
            run "caddy version" "caddy_version.txt" docker exec edge-caddy caddy version
            run "caddy validate" "caddy_validate.txt" docker exec edge-caddy caddy validate --config /etc/caddy/Caddyfile

            # Check if ss is available inside the container
            if docker exec edge-caddy command -v ss >/dev/null 2>&1; then
              run "caddy container listeners" "caddy_container_ss.txt" docker exec edge-caddy ss -lntup
            else
              gap "ss not available in caddy container (or container down)"
            fi
        fi
    fi
  )
else
  gap "docker missing; cannot check container port publish."
fi

###############################################################################
# Q6: WireGuard Routing/NAT korrekt?
###############################################################################
say "Q6: WireGuard routing/NAT"
if have sysctl; then
  run "sysctl ip_forward" "ip_forward.txt" sysctl net.ipv4.ip_forward
  if sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q '^1$'; then
    ok "ip_forward=1"
  else
    gap "ip_forward is not 1 (WG->LAN likely broken)."
  fi
else
  gap "sysctl missing; cannot verify ip_forward."
fi

if have iptables; then
  run "iptables nat POSTROUTING rules" "iptables_nat_postrouting.txt" sudo iptables -t nat -S POSTROUTING
  nat_rules="$(sudo iptables -t nat -S POSTROUTING 2>/dev/null || true)"

  # 1. Generic Check: Any MASQUERADE for WG Subnet?
  # Order-agnostic check: subnet literal + MASQUERADE literal
  if echo "$nat_rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "-j MASQUERADE" >/dev/null; then
      ok "Found MASQUERADE for WG subnet (generic)."

      # 2. Specific Check: Does it match the expected interface?
      # Order-agnostic check: subnet + interface + MASQUERADE
      if echo "$nat_rules" | grep -F -- "-s $WG_SUBNET" | grep -F -- "-o $EXPECTED_LAN_IF" | grep -F -- "-j MASQUERADE" >/dev/null; then
          note "MASQUERADE matches expected LAN interface ($EXPECTED_LAN_IF)."
      else
          note "MASQUERADE rule does NOT match expected LAN interface ($EXPECTED_LAN_IF). Verify manually."
      fi
  else
      gap "No MASQUERADE rule for WG subnet found. Verify NAT."
  fi
else
  gap "iptables missing; cannot verify NAT."
fi

if have wg; then
  # sanitize: remove private key lines & endpoints
  run "wg show (sanitized)" "wg_show_sanitized.txt" \
    bash -c "sudo wg show | grep -vE 'private key|endpoint:' || true"

  # Check AllowedIPs server-side minimal (peer should be /32)
  if sudo wg show 2>/dev/null | grep -qE "allowed ips:.*10\.7\.0\.2/32"; then
    ok "Found peer AllowedIPs 10.7.0.2/32 (heuristic)."
  else
    gap "Peer AllowedIPs not confidently matching 10.7.0.2/32. Verify wg0.conf."
  fi
else
  gap "wg not available; cannot verify WireGuard state."
fi

###############################################################################
# Q7: DNS coherence quick checks (no full dumps)
###############################################################################
say "Q7: DNS coherence checks"
if have dig; then
  run "dig FQDN via localhost" "dns_dig_local.txt" dig +short leitstand.heimgewebe.home.arpa @127.0.0.1
else
  gap "dig missing; cannot test DNS resolution."
fi

if have getent; then
  run "getent hosts FQDN" "dns_getent_fqdn.txt" getent hosts leitstand.heimgewebe.home.arpa
  run "getent hosts short" "dns_getent_short.txt" getent hosts leitstand
else
  gap "getent missing; cannot check NSS resolution."
fi

###############################################################################
# Summary
###############################################################################
say "SUMMARY"
summary="$SNAPSHOT_DIR/SUMMARY.md"
{
  echo "# Audit Snapshot $TIMESTAMP"
  echo
  echo "**Host:** $(hostname)"
  echo "**Date:** $(date -Is)"
  echo
  echo "## Checked Questions"
  echo "- Q1 IPv6 disabled (host + listeners + docker)"
  echo "- Q2 Firewall backend consistency (iptables/nft)"
  echo "- Q3 DOCKER-USER guard plausibility"
  echo "- Q4 Firewall manager conflicts (ufw/firewalld)"
  echo "- Q5 Port exposure (QUIC, Caddy admin, docker publish, caddy internals)"
  echo "- Q6 WireGuard routing/NAT"
  echo "- Q7 DNS coherence (minimal)"
  echo
  echo "## Gaps / Alerts"
  if [ -f "$SNAPSHOT_DIR/GAPS.txt" ]; then
    sed 's/^/ - /' "$SNAPSHOT_DIR/GAPS.txt"
  else
    echo "- None detected."
  fi
  echo
  echo "## Notes"
  echo "- Review snapshot contents before sharing."
  echo "- Snapshot may include real IPs/subnets (by design)."
  echo "- No private keys should be present; WG endpoints removed."
} > "$summary"

echo "Audit complete: $SNAPSHOT_DIR"
echo "Open: $summary"
