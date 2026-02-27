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

say "invariants (static analysis)"
if [ -f "scripts/ci/check-runbook-invariants.sh" ]; then
  bash scripts/ci/check-runbook-invariants.sh || exit 1
else
  warn "Invariant script not found (scripts/ci/check-runbook-invariants.sh)"
fi

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
  if docker info >/dev/null 2>&1; then
    docker ps --format 'table {{.Names}}\t{{.Ports}}' || true
  else
    warn "docker binary present but daemon unreachable (permissions/stopped?)"
  fi
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
          # We search for lines containing subnet AND tcp AND port AND ACCEPT.
          # Using regex boundaries ([^0-9]|$) to avoid matching 8080/8443 false positives.

          # LAN
          # Look for: -s LAN ... -p tcp ... --dport 80/443 or multiport ... -j ACCEPT
          # Tightened multiport match: -m multiport --dports (80,443|443,80) with boundaries
          if echo "$docker_user_rules" | grep -F -- "-s $LAN_SUBNET" | grep -qE -- "-p tcp .*(--dport (80|443)([^0-9]|$)|-m multiport --dports (80,443|443,80)([^0-9]|$)).*-j ACCEPT"; then
              ok "LAN ($LAN_SUBNET) -> TCP 80/443 allowed (heuristic)"
          else
              warn "LAN ($LAN_SUBNET) allow rule for TCP 80/443 not confident. MANUAL REVIEW REQUIRED."
          fi

          # WireGuard
          if echo "$docker_user_rules" | grep -F -- "-s $WG_SUBNET" | grep -qE -- "-p tcp .*(--dport (80|443)([^0-9]|$)|-m multiport --dports (80,443|443,80)([^0-9]|$)).*-j ACCEPT"; then
              ok "WG ($WG_SUBNET) -> TCP 80/443 allowed (heuristic)"
          else
              warn "WG ($WG_SUBNET) allow rule for TCP 80/443 not confident. MANUAL REVIEW REQUIRED."
          fi

          # UDP 443 (QUIC) checks if enabled
          if [ "${ALLOW_QUIC}" = "1" ]; then
              # Tightened UDP match: require --dport prefix
              if echo "$docker_user_rules" | grep -i "udp" | grep -E -- "(--dport 443([^0-9]|$)|-m multiport --dports 443([^0-9]|$))" | grep -q -- "-j ACCEPT"; then
                   ok "UDP 443 allow rule found (heuristic)"
              else
                   warn "UDP 443 allow rule missing/unverified (Check DOCKER-USER)"
              fi
          fi

          # Drop Rest Logic: Any Drop/Reject for 80/443 OR generic catch-all
          if echo "$docker_user_rules" | grep -qE -- "-p tcp .*(--dport (80|443)([^0-9]|$)|-m multiport --dports (80,443|443,80)([^0-9]|$)).*-j (DROP|REJECT)"; then
              ok "Explicit Drop/Reject rule for TCP 80/443 found (heuristic)"
          elif echo "$docker_user_rules" | grep -E -q -- "-j (DROP|RETURN|REJECT)$"; then
              # RETURN is risky if parent chain doesn't drop, but often used in chains.
              # Ideally we want a clear DROP.
              warn "Generic Drop/Return/Reject policy found (weak heuristic). Verify DOCKER-USER behavior."
          else
              warn "No explicit Drop/Return policy found for TCP 80/443 (verify manually)"
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

say "edge runtime checks"
EDGE_DIR="/opt/heimgewebe/edge"
if [ -d "$EDGE_DIR" ]; then
    # 1. Check Docker Compose Config
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker compose -f "$EDGE_DIR/docker-compose.yml" config >/dev/null 2>&1; then
             ok "Edge Docker Compose config valid"
        else
             warn "Edge Docker Compose config INVALID (check $EDGE_DIR/docker-compose.yml)"
        fi
    else
        warn "Skip: Docker checks (daemon unreachable)"
    fi

    # 2. Port Matrix Guard (Strict Internal Policy)
    if command -v ss >/dev/null 2>&1; then
        # Check 1: App Ports (8080/5432) -> Invariant Violation if PUBLICLY exposed or via docker-proxy
        # Logic:
        # - WARN if docker-proxy on 8080/5432 (published container port).
        # - WARN if listening on 0.0.0.0 or [::] (public exposure).
        # - ALLOW if listening ONLY on 127.0.0.1 (e.g. code-server ssh tunnel).

        # Robust filtering to detect exposure
        # We look for ANY listener on 8080/5432.
        # If found, we check if it is NOT loopback (127.0.0.1 or ::1).
        # OR if it is docker-proxy (regardless of bind, usually implies publish).

        # Force list context by echo to avoid grep failing on empty input
        listeners_8080_5432=$(ss -lntup | grep -E ':(8080|5432)\b' || true)

        if [ -n "$listeners_8080_5432" ]; then
            # Heuristic: Check for public exposure or docker-proxy
            # 1. docker-proxy is always suspicious for App ports
            # 2. 0.0.0.0 or [::] or * means public bind
            # 3. If NONE of those, it might be 127.0.0.1 (Allowed)

            # Check for public binding (0.0.0.0 or [::] or *) OR docker-proxy process name
            # Note: 0.0.0.0:8080 matches '0\.0\.0\.0:'
            # Note: docker-proxy process name often appears in users:(("docker-proxy"...))

            # The regex 0\.0\.0\.0 matches anywhere, so 0.0.0.0:8080 is caught.
            # * matches literal * (as in *:8080 or * 8080).
            # Debug: what are we matching against?
            # echo "DEBUG: listeners='$listeners_8080_5432'"

            # Using basic grep without -E/-F if possible or simple pipes to avoid issues
            # We check variable content directly
            # Check for common public bindings (0.0.0.0, ::, *) or docker-proxy
            # Note: We use grep -F for fixed strings where possible, except * which needs escaping or -F
            # Check for common public bindings:
            # 0.0.0.0, [::], *, or docker-proxy process name.

            is_exposed=0
            if echo "$listeners_8080_5432" | grep "0.0.0.0" >/dev/null 2>&1; then is_exposed=1; fi
            if echo "$listeners_8080_5432" | grep "::" >/dev/null 2>&1; then is_exposed=1; fi
            if echo "$listeners_8080_5432" | grep "*" >/dev/null 2>&1; then is_exposed=1; fi
            if echo "$listeners_8080_5432" | grep "docker-proxy" >/dev/null 2>&1; then is_exposed=1; fi

            if [ "$is_exposed" -eq 1 ]; then
                 warn "App Ports (8080/5432) PUBLICLY exposed (docker-proxy or 0.0.0.0)! VIOLATION."
            # Check for ANY line that does NOT contain localhost IP.
            # grep -v returns success (0) if it prints anything (i.e. finds a non-matching line).
            elif echo "$listeners_8080_5432" | grep -v "127.0.0.1" | grep -v "::1" >/dev/null 2>&1; then
                 # If not loopback and not caught above (weird bind?) -> Warn
                 warn "App Ports (8080/5432) exposed on non-loopback interface! VIOLATION."
            else
                 ok "App Ports (8080/5432) active but localhost-only (Allowed for dev tools)."
            fi
        else
            ok "App Ports (8080/5432) internal only (Correct)"
        fi

        # Check 2: Drift Detection (9081)
        if ss -lntup | grep -E ':9081\b' >/dev/null 2>&1; then
            warn "Port 9081 exposed! This is legacy drift (Strict Policy: 9081 removed)."
        else
            ok "Port 9081 not present (Correct)"
        fi

        # 8081: Pi-hole FTL (Owner Check)
        if ss -lntup | grep -E ':8081' >/dev/null 2>&1; then
            # We attempt to check the process name, but ss output varies.
            if ss -lntup | grep -E ':8081' | grep -iE 'pihole-FTL|lighttpd' >/dev/null 2>&1; then
                 ok "Port 8081 active (Pi-hole FTL/Lighttpd identified)"
            else
                 # Drift Detection: Warn if Weltgewebe/Java/Go seems to be using 8081
                 if ss -lntup | grep -E ':8081' | grep -iE 'java|weltgewebe|go' >/dev/null 2>&1; then
                     warn "Port 8081 stolen by App/Weltgewebe! (Invariante 1 violation). 8081 belongs to Pi-hole."
                 else
                     warn "Port 8081 in use by unknown process! (Expected: Pi-hole FTL). Check Drift."
                 fi
            fi
        fi
    fi

    # 3. Check Cloudflare Headers (Drift)
    if command -v curl >/dev/null 2>&1; then
        # Edge Health Check via 9081 is REMOVED (Internal Policy).
        # We only check Cloudflare Headers if we can resolve the domain.

        # Check for Cloudflare headers (if domain resolves and CA is present)
        # Using grep instead of rg (ripgrep) for standard compliance.
        # Anchor to start of header line to avoid false positives.
        if [ -f "$EDGE_DIR/certs/caddy-local-root.crt" ] && getent hosts weltgewebe.home.arpa >/dev/null 2>&1; then
             if curl --cacert "$EDGE_DIR/certs/caddy-local-root.crt" -Is https://weltgewebe.home.arpa/ | grep -iE '^(server:[[:space:]]*cloudflare|cf-ray:)' >/dev/null 2>&1; then
                  warn "Cloudflare headers detected on weltgewebe.home.arpa! (Drift: Tunnel active?)"
             else
                  ok "No Cloudflare headers on weltgewebe.home.arpa"
             fi
        fi
    fi
else
    echo "Info: Edge directory $EDGE_DIR not found (skipping Edge specific checks)"
fi


echo
echo "Done. If any WARN lines appeared, treat as drift until explained."
