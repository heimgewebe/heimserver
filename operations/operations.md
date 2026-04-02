---
id: operations
role: action
reference_policy: optional
status: active
canonicality: canonical
doc_type: policy
title: Operations Policy
summary: Operational procedures protocol
last_reviewed: 2026-02-13
depends_on:
  - runtime/runtime.md
verifies_with:
  - ops/audit/collect.sh
---

# operations.md

Betriebs- und Eingriffsprotokoll
⛔️ OPERATIVES DOKUMENT · KANONISCH

Stand: 2026-02-13
Scope: Heimserver · Heimgewebe · WireGuard · Pi-hole · Caddy

---

## 0. Betriebsphilosophie

These: Betrieb ist Wartung.
Antithese: Betrieb ist Zustandskontrolle.
Synthese: Betrieb ist Drift-Vermeidung.

Destabilisierung:
Nicht „läuft es?“ ist die Frage.
Sondern: „Läuft es kohärent mit der Architektur?“

---

## 1. Minimaler Gesundheitscheck

Container

`docker ps` und `docker compose -p weltgewebe ps`

Erwartung:
	•	`edge-caddy` → Up
	•	`dns-pihole` → Up (healthy)
	•	`deploy-leitstand-1` → Up
	•	Weltgewebe-Services (`api`, `nats`, `db`) → Up

Kein Restarting.
Kein Exited.

---

DNS

`dig +short leitstand.heimgewebe.home.arpa @127.0.0.1`

Erwartung:

`192.168.178.46`


---

HTTP

`curl -I http://leitstand.heimgewebe.home.arpa`

Erwartung:

`308 Permanent Redirect`


---

HTTPS (Server-intern)

`curl -k -I https://leitstand.heimgewebe.home.arpa`

Erwartung:

`200 OK`


---

WireGuard

`sudo wg show`

Erwartung:
	•	latest handshake < 60 Sekunden
	•	Transfer steigend bei Nutzung

---

## 2. Standard-Wiederherstellung

### 2.1 Caddy Crashloop

Symptom:

`Restarting (1)`

Vorgehen:

```bash
docker logs edge-caddy
# Validierung (Host-Pfad):
docker compose -f /opt/heimgewebe/edge/docker-compose.yml exec edge-caddy caddy validate --config /etc/caddy/Caddyfile
# Oder wenn Container tot:
docker run --rm -v /opt/heimgewebe/edge/Caddyfile:/etc/caddy/Caddyfile caddy:2.8.4 caddy validate --config /etc/caddy/Caddyfile
```

Häufigster Fehler:
Syntax im Caddyfile.

Nach Fix:

`docker compose up -d --force-recreate caddy`


---

### 2.2 DNS antwortet nicht

Check:

`sudo docker exec dns-pihole pihole status`

Wenn FTL läuft:

`sudo docker exec dns-pihole pihole reloaddns`

Wenn etc_dnsmasq_d deaktiviert:

`grep etc_dnsmasq_d /etc/pihole/pihole.toml`

Muss:

`etc_dnsmasq_d = true`


---

### 2.3 iPad kann Seite nicht öffnen

Checkfolge:
	1.	WireGuard aktiv?
	2.	DNS im WG-Profil = 192.168.178.46?
	3.	AllowedIPs korrekt?
	4.	tcpdump auf wg0 prüfen:

`sudo tcpdump -ni wg0 port 53 or port 80 or port 443`

Wenn DNS an 192.168.178.1 geht → WG DNS falsch.

---

### 2.x QUIC/HTTP3 bewusst aktivieren (Ausnahmefall)

Default ist QUIC AUS. Aktivierung nur wenn ausdrücklich gewollt:
- Caddy global: `servers { protocols h1 h2 }` entfernen/anpassen (h3 zulassen)
- Compose: UDP 443 publish hinzufügen
- Preflight: `ALLOW_QUIC=1` setzen und dokumentieren ([`constitution.md`](../architecture/constitution.md) / [`network.md`](../architecture/network.md))

---

## 3. WireGuard Wartung

Peer prüfen

`sudo wg show`

AllowedIPs für iPad:

`10.7.0.2/32`

Nicht:

`192.168.178.0/24`
`0.0.0.0/0`

Routing erfolgt serverseitig via NAT.

---

NAT prüfen

`sudo iptables -t nat -L POSTROUTING -n -v`

Erwartung:

`MASQUERADE  10.7.0.0/24  → eno2`


---

IP-Forward prüfen

`sysctl net.ipv4.ip_forward`

Muss:

`= 1`


---

## 4. Zertifikatswartung

Root-CA liegt in:

`/opt/heimgewebe/edge/certs/caddy-local-root.crt`

Bei Clientproblemen:
	•	CA neu exportieren
	•	auf Client installieren
	•	iOS → Zertifikatsvertrauen aktivieren

---

## 5. DNS-Drift-Test

Einmal im Monat:

`grep -R home.arpa /opt/heimgewebe`

Es darf nur vorkommen:
	•	Pi-hole dnsmasq.d
	•	Caddyfile
	•	Dokumentation

Keine Schatten-Domains.

---

## 6. Backup-Strategie

Konfigurationskritisch:
	•	`/opt/heimgewebe/edge/Caddyfile`
	•	`/opt/heimgewebe/dns/pihole/`
	•	`/etc/wireguard/wg0.conf`

Backup:

Warnung: Backup enthält unverschlüsselte Secrets/Keys! Nur verschlüsselt speichern (z.B. age/gpg), niemals ins Repo committen.

```bash
tar czf heimserver-config-$(date +%F).tar.gz \
/opt/heimgewebe \
/etc/wireguard
```


---

## 7. Monitoring-Minimum

Kein externes Monitoring.

Aber:
	•	`docker ps`
	•	`wg show`
	•	`dig`
	•	`curl`

Reicht für Heimmaßstab.

---

## 8. Notfall-Reset

Wenn alles bricht:
	1.	Stoppe Caddy
	2.	Stoppe Pi-hole
	3.	Prüfe DNS lokal
	4.	Starte Pi-hole
	5.	Starte Caddy

Reihenfolge ist wichtig.

---

## 9. Systemische Risiken

Hoch:
	•	parallele DNS-Resolver
	•	Router-DNS ≠ Pi-hole
	•	falsche AllowedIPs

Mittel:
	•	Docker-Netz-Divergenz
	•	IPv6 unerwartet aktiv

Niedrig:
	•	TLS interner CA

---

## 10. Essenz

Heimserver ist kein Server.
Er ist ein kohärenter Zustand.

Betrieb heißt:
Diesen Zustand gegen Drift verteidigen.

---

## Unsicherheitsgrad

0.12

Ursachen:
	•	IPv6-Verhalten nicht vollständig getestet
	•	Keine automatisierte Config-Validierung
	•	Router-Konfiguration nicht versioniert

Interpolationsgrad:

0.06

Annahmen:
	•	Fritzbox DNS konsistent
	•	Kein zweiter Resolver aktiv
	•	Keine VLAN-Segmentierung aktiv

---

Humor (trocken):

Ein Heimserver stirbt selten spektakulär.
Er stirbt durch inkonsistente Annahmen.

Und Annahmen sind wie offene Ports.
Irgendwann benutzt sie jemand.
