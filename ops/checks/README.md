# ops/checks — Belegbare Operativ-Checks

Prinzip:
- Jeder Check ist ein Belegpfad für Aussagen in `heimserver.runtime.md` und den Architektur-Docs.
- Output gehört in `ops/audit/snapshots/<timestamp>/` (gitignored).

## Check-Matrix (Kanon → Beleg)

### Listener / Exposition

Belegt:
- keine Host-Listener auf 0.0.0.0:80/:443
- kein Caddy-Admin-Port (:2019) erreichbar

Commands:
    ss -lntup | egrep '(:80|:443|:2019)\b' || true

### Docker publish (Caddy loopback-caged)

Belegt:
- 80/tcp und 443/tcp sind nur auf 127.0.0.1 published

Commands:
    docker ps --format 'table {{.Names}}\t{{.Ports}}'

### DOCKER-USER Chain (Caging 80/443)

Belegt:
- allow LAN/WG für 80/443, drop rest

Commands:
    sudo iptables -S DOCKER-USER

### netfilter-persistent Persistenz

Belegt:
- rules.v4/v6 existieren
- Service startet sauber

Commands:
    systemctl status netfilter-persistent --no-pager
    ls -la /etc/iptables/

### WireGuard

Belegt:
- wg0 up, peers sichtbar, handshake/rx/tx vorhanden

Commands:
    sudo wg show
    ip -br link | sed -n '1,120p'

### sysctl forward/rp_filter

Belegt:
- net.ipv4.ip_forward = 1
- rp_filter = 2 (loose)

Commands:
    sysctl net.ipv4.ip_forward
    sysctl net.ipv4.conf.all.rp_filter
    sysctl net.ipv4.conf.default.rp_filter

## Scripts

- `preflight.sh` — schnelle Assertions, keine Änderungen
- `snapshot.sh` — schreibt strukturiert in audit-snapshots
- `redact_snapshot.sh` — best-effort Redaction (vor dem Teilen prüfen)
