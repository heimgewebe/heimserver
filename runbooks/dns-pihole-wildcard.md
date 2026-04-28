# ops.dns-pihole-wildcard-home-arpa

> **Status: superseded / historical**
>
> Dieses Runbook beschreibt DNS auf dem Heimserver (`192.168.178.46`) und gilt nur noch als Migrationsreferenz.
> Aktuelle Zielpfade:
> - `runbooks/heimberry-bootstrap.md`
> - `runbooks/dns-migration.md`

Status: HISTORISCH / DEPRECATED
Scope: Heimserver (192.168.178.46)
System: Pi-hole (Docker)
Namespace: heimgewebe.home.arpa

---

## 1. Zweck

Wildcard-DNS für alle Subdomains unter:

    *.heimgewebe.home.arpa

Ziel:
- stabile interne Namensauflösung
- keine mDNS-Kollision (.local vermeiden)
- RFC-konformer privater Namespace

---

## 2. Namespace-Entscheidung

Verwendet wird:

    home.arpa

Begründung:
- RFC 8375 reserviert `home.arpa` explizit für Heimnetzwerke
- `.local` ist für mDNS reserviert → vermeiden
- `.lan` ist nicht standardisiert

---

## 3. Technische Implementierung

Datei (Host):

    /opt/heimgewebe/dns/pihole/etc-pihole/dnsmasq.d/99-heimgewebe.conf

Inhalt:

    address=/.heimgewebe.home.arpa/192.168.178.46

Wirkung:
Alle Subdomains unter `heimgewebe.home.arpa`
zeigen auf 192.168.178.46.

---

## 4. Docker-Mount

Container: dns-pihole

Mount:

    /opt/heimgewebe/dns/pihole/etc-pihole
        →
    /etc/pihole

Verifikation:

    docker inspect dns-pihole | grep -A5 Mounts

---

## 5. Neustart DNS

    docker exec dns-pihole pihole restartdns reload

oder vollständig:

    docker restart dns-pihole

---

## 6. Tests

### Direkt im Container

    docker exec dns-pihole dig leitstand.heimgewebe.home.arpa +short

Erwartung:

    192.168.178.46

### Vom Host

    dig @192.168.178.46 leitstand.heimgewebe.home.arpa +short

### Client-Test

Client muss Pi-hole (192.168.178.46) als DNS verwenden.

---

## 7. Troubleshooting

### NXDOMAIN

- Prüfen, ob Datei existiert:

    ls -l /etc/pihole/dnsmasq.d/

- DNS reload ausführen
- Client DNS Cache flushen

### Clients nutzen nicht Pi-hole

Prüfen:

    nmcli dev show | grep DNS

oder Router-DNS prüfen.

---

## 8. Sicherheitsbetrachtung

- Nur internes Netz
- Keine öffentliche Auflösung
- Keine Split-DNS-Konflikte
- Keine mDNS-Leaks

---

## 9. Änderungslogik

Änderungen an Namespace oder IP
müssen dokumentiert werden.

DNS ist Infrastruktur — kein Experiment.
