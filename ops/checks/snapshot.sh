#!/usr/bin/env bash
set -euo pipefail

# Snapshot: schreibt einen Audit-Snapshot (Textdateien) nach außerhalb von Git.
# Default-Zielpfad (kanonisch): /home/alex/server-facts/audit-snapshots/<timestamp>
#
# Usage:
#   bash ops/checks/snapshot.sh
#   SNAPSHOT_DIR=/path/to/dir bash ops/checks/snapshot.sh

ts="$(date +"%Y%m%d-%H%M%S")"
default_dir="/home/alex/server-facts/audit-snapshots/${ts}"
out="${SNAPSHOT_DIR:-$default_dir}"

mkdir -p "$out"

say() { printf "\n== %s ==\n" "$*"; }
write() {
  local name="$1"
  shift
  local file="$out/$name"
  {
    echo "# snapshot.file $name"
    echo "# snapshot.ts   $ts"
    echo "# snapshot.host $(hostname 2>/dev/null || true)"
    echo "# snapshot.cwd  $(pwd)"
    echo
    "$@"
  } >"$file" 2>&1 || true
  echo "WROTE: $file"
}

say "snapshot destination"
echo "$out"

say "basic"
write "host.txt" bash -lc 'hostname; echo; uname -a; echo; date -Is'
write "ip_link_brief.txt" bash -lc 'ip -br link'
write "ip_addr_brief.txt" bash -lc 'ip -br addr'
write "routes.txt" bash -lc 'ip route; echo; ip -6 route || true'

say "listeners"
if command -v ss >/dev/null 2>&1; then
  write "ss_listeners.txt" bash -lc 'ss -lntup; echo; ss -lunp || true'
else
  write "ss_listeners.txt" bash -lc 'echo "ss not available"'
fi

say "docker"
if command -v docker >/dev/null 2>&1; then
  write "docker_ps_ports.txt" bash -lc "docker ps --format 'table {{.Names}}\t{{.Ports}}'"
  write "docker_network_ls.txt" bash -lc 'docker network ls'
else
  write "docker_ps_ports.txt" bash -lc 'echo "docker not available"'
  write "docker_network_ls.txt" bash -lc 'echo "docker not available"'
fi

say "iptables / netfilter-persistent"
if command -v iptables >/dev/null 2>&1; then
  write "iptables_rules_runtime.txt" bash -lc 'sudo iptables -S; echo; sudo iptables -S DOCKER-USER || true'
  write "iptables_save.txt" bash -lc 'sudo iptables-save'
else
  write "iptables_rules_runtime.txt" bash -lc 'echo "iptables not available"'
  write "iptables_save.txt" bash -lc 'echo "iptables not available"'
fi

if command -v systemctl >/dev/null 2>&1; then
  write "systemd_netfilter_persistent.txt" bash -lc 'systemctl status netfilter-persistent --no-pager || true'
else
  write "systemd_netfilter_persistent.txt" bash -lc 'echo "systemctl not available"'
fi

say "sysctl"
write "sysctl_forwarding.txt" bash -lc 'sysctl net.ipv4.ip_forward; sysctl net.ipv4.conf.all.rp_filter; sysctl net.ipv4.conf.default.rp_filter'

say "wireguard"
if command -v wg >/dev/null 2>&1; then
  write "wg_show.txt" bash -lc 'sudo wg show'
else
  write "wg_show.txt" bash -lc 'echo "wg not available"'
fi

say "dns"
write "dns_getent_hosts.txt" bash -lc 'getent hosts heimserver || true; getent hosts leitstand.lan || true'
if command -v resolvectl >/dev/null 2>&1; then
  write "dns_resolvectl_status.txt" bash -lc 'resolvectl status || true'
else
  write "dns_resolvectl_status.txt" bash -lc 'echo "resolvectl not available"'
fi

say "done"
echo "Snapshot complete: $out"
echo
echo "Reminder: This directory is intentionally outside Git."
