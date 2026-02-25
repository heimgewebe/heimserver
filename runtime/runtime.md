# runtime.md

Status: Operativ kanonisch
Scope: Laufzeit-Realität des Heimservers (nicht Architekturvision)

**Legende Status-Tags:**
- **Observed:** Automatisch durch Audit (z.B. `ops/audit/collect.sh`) beobachtet.
- **Policy:** Durch Verfassung ([`constitution.md`](../architecture/constitution.md)) vorgegeben.
- **Assumed:** Annahme, muss noch technisch verifiziert werden.

---

## 0. Zweck

Dieses Dokument beschreibt den tatsächlichen Laufzeitzustand des Heimservers.

Nicht:
	•	Wunscharchitektur
	•	Konzept
	•	Naming
	•	Netzplanung

Sondern:

Was läuft wirklich.
Was muss invariant sein.
Wie Drift erkannt wird.

---

## 1. Identitätsschicht

### 1.1 Host-Identität
	•	Hostname: heimserver
	•	LAN-IP: 192.168.178.46
	•	WireGuard-IP: 10.7.0.1
	•	Rolle: Heimgewebe Edge + DNS + VPN + Reverse Proxy

Invariante:

Heimserver ist Trust-Pivot des Heimnetzes.

Audit prüfen:

`hostnamectl`
`ip -br a` (Beleg: `ss_lntup.txt` / manuell)


---

### 1.2 Kernel-Funktionen

Erforderlich:

`sysctl net.ipv4.ip_forward`

Soll:

`net.ipv4.ip_forward = 1` (Status: Observed; Beleg: `sysctl_ip_forward.txt`)

Invariante:

Ohne ip_forward ist WG-LAN-Access unmöglich.

---

## 2. Netz-Schicht

### 2.1 Interfaces

Erwartet:

| Interface | Zweck |
|---|---|
| eno2 | LAN |
| wg0 | VPN |
| docker0 / br-* | Container |

Prüfen:

`ip -br a`
`ip route`


---

### 2.2 Routing-Invariante

Erwartet:
	•	Default → Fritzbox (192.168.178.1)
	•	10.7.0.0/24 → wg0
	•	192.168.178.0/24 → eno2

Invariante:

Kein asymmetrisches Routing.

Audit (Status: Observed):
	•	Reverse Path Filter: Aktiv
	•	sysctl net.ipv4.conf.all.rp_filter (Status: OK; Beleg: `sysctl_rp_filter.txt`)


---

### 2.3 WireGuard

Status:

`sudo wg show`

Peer muss enthalten:

`allowed ips: 10.7.0.2/32`

Nicht:

`0.0.0.0/0`

Invariante:

Split-Tunnel ist Default. Kein Full-Tunnel ohne bewusste Entscheidung.

Drift-Indikator:
	•	Handshake OK
	•	aber 0 Traffic
→ AllowedIPs oder Routing falsch

---

### 2.4 NAT-Regel

Erwartet:

`sudo iptables -t nat -S`

Muss enthalten:

`-A POSTROUTING -s 10.7.0.0/24 -o eno2 -j MASQUERADE`

Invariante:

NAT nur für WireGuard-Netz.

Audit-Lücke:
	•	nftables vs iptables-nft Konsistenz prüfen.

---

## 3. DNS-Schicht

### 3.1 Pi-hole

Container: dns-pihole

Prüfen:

`docker ps`

Invariante:

Pi-hole ist alleiniger DNS im Heimnetz.

---

### 3.2 home.arpa Zone

Canonical Zone:

`*.heimgewebe.home.arpa`

Auflösung via:

`address=/leitstand.heimgewebe.home.arpa/192.168.178.46`

Prüfen:

`dig leitstand.heimgewebe.home.arpa @127.0.0.1`

Invariante:

home.arpa niemals extern forwarden.

---

### 3.3 fritz.box Conditional Forwarding

Konfig:

`server=/fritz.box/192.168.178.1`
`rev-server=192.168.178.0/24,192.168.178.1`

Invariante:

fritz.box wird nie über 8.8.8.8 aufgelöst.

Drift-Indikator:

cached heimserver.fritz.box is NXDOMAIN

Audit (Status: Assumed - derzeit nicht im collect.sh):

`docker exec dns-pihole grep -R fritz.box /etc/dnsmasq.d`


---

### 3.4 DNS-Splitbrain-Vermeidung

Empfohlen:

Fritzbox DHCP → DNS = 192.168.178.46

Nicht:

Manuelle DNS pro Client

Invariante:

Kein Client-Sonderzustand.

---

## 4. Proxy-Schicht (Caddy)

Container: edge-caddy

---

### 4.1 Site-Block Invariante

Canonical Hosts:

leitstand.heimgewebe.home.arpa
weltgewebe.home.arpa
api.weltgewebe.home.arpa

Caddy Status:
	•	Version: Observed (v2.8.4; Beleg: `caddy_version.txt`)
	•	Config: Observed (caddy validate OK; Beleg: `caddy_validate.txt`)

Caddyfile:

```
http://leitstand.heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://leitstand.heimgewebe.home.arpa {
  reverse_proxy deploy-leitstand-1:3000
  tls internal
}
```

Invariante:

Kein alter Host wie leitstand.home aktiv.

Audit prüfen:

`curl -i http://192.168.178.46 -H "Host: leitstand.heimgewebe.home.arpa"`

Erwartet:

308 Redirect


---

### 4.2 TLS

Verwendet:

`tls internal`

Root CA exportiert nach:

`/opt/heimgewebe/edge/certs/caddy-local-root.crt`

Invariante:

iPad muss Root-CA vertrauen.

Drift-Indikator:

no peer certificate available


---

### 4.3 Container-Netz

edge-caddy muss in:
	•	edge
	•	heimnet

Invariante:

Reverse Proxy darf Upstream per Container-DNS auflösen.

Audit prüfen:

`docker inspect edge-caddy | jq`

---

## 5. Container-Schicht

### 5.1 Aktive Kerncontainer

Erwartete Kernrollen:

| Container | Rolle | Kritikalität |
|---|---|---|
| dns-pihole | DNS / Resolver | kritisch |
| edge-caddy | Reverse Proxy / TLS | kritisch |
| deploy-leitstand-1 | UI / Leitstand | hoch |
| weltgewebe-api | API Backend | hoch |

Audit (Ist-Zustand 2026-02-13; Beleg: `docker_ps.txt`):

| Container | Rolle | Status | Netzwerke |
|---|---|---|---|
| dns-pihole | DNS | healthy | host (implizit 53/tcp+udp, 80/tcp) |
| edge-caddy | Proxy | Up | edge, heimnet |
| deploy-leitstand-1 | Leitstand | Up | deploy_default, heimnet |
| dns-unbound | Resolver | healthy | dns_default |
| weltgewebe-api | API | Up | - |

Invariante:

Kein Container läuft ohne klar definierte Rolle.

---

### 5.2 Netzwerke

Erwartete Docker-Netze (Audit-Ergebnis):
	•	edge
	•	heimnet
	•	dns_default
	•	deploy_default
	•	compose_default
	•	bridge
	•	host
	•	none

Audit:

`docker network ls`
`docker network inspect heimnet`

Invariante:

Reverse Proxy und Zielservice müssen im selben Netz sein.

Drift-Indikator:
	•	reverse_proxy Dial schlägt fehl
	•	502 Bad Gateway

---

### 5.3 Published Ports (Ist-Zustand 2026-02-13; Beleg: `ss_lntup.txt`)

| Port | Proto | Dienst | Binding | Anmerkung |
|---|---|---|---|---|
| 53 | TCP/UDP | Pi-hole (Host-Net) | 0.0.0.0, :: | DNS Service |
| 80 | TCP | Caddy | 0.0.0.0, :: | HTTP -> Redirect |
| 443 | TCP | Caddy | 0.0.0.0, :: | HTTPS |
| 51820 | UDP | WireGuard | 0.0.0.0, :: | VPN Ingress |
| 22 | TCP | SSHD | 0.0.0.0, :: | Admin Access |

Local Listeners (127.0.0.1 Only):

| Port | Proto | Dienst | Binding | Anmerkung |
|---|---|---|---|---|
| 3000 | TCP | deploy-leitstand-1 | 127.0.0.1 | |
| 5335 | TCP/UDP | dns-unbound | 127.0.0.1 | Pi-hole Upstream |
| 8080 | TCP | code-server | 127.0.0.1 | SSH-Tunnel Access |
| 8081 | TCP | edge-caddy | 127.0.0.1 | Health/Metrics |

Caddy Admin:
Port 2019 ist NICHT published (nur container-intern erreichbar).

HTTP/3 (QUIC):
- Status: Observed = deaktiviert (kein UDP 443 publish).
- Policy: Default AUS; Aktivierung nur bewusst (siehe constitution + preflight `ALLOW_QUIC=1`).

Audit:

`ss -lntup`

Invariante:

Keine unnötigen offenen Ports.

Audit-Lücke:
	•	Port-Exposure-Review fehlt dokumentiert.

---

## 6. Persistenz-Zonen

### 6.1 Caddy

Volumes:
	•	edge_caddy_data
	•	edge_caddy_config

Pfad Host:

`/opt/heimgewebe/edge/`

Invariante:

Caddyfile wird als bind-mount read-only gemountet.

Audit:

`docker inspect edge-caddy | jq '.Mounts'`


---

### 6.2 Pi-hole

Wichtige Pfade:
	•	`/etc/pihole`
	•	`/etc/dnsmasq.d`

Invariante:

`etc_dnsmasq_d = true`

Audit:

`grep etc_dnsmasq_d /opt/heimgewebe/dns/pihole/etc-pihole/pihole.toml`


---

### 6.3 WireGuard

Konfig:

`/etc/wireguard/wg0.conf`

Invariante:

AllowedIPs minimal
PrivateKey niemals versioniert

Audit-Lücke:
	•	wg0.conf Redacted Snapshot fehlt dokumentiert.

---

## 7. Systemd-Schicht

Erwartete Units:

| Unit | Status |
|---|---|
| wg-quick@wg0 | active |
| docker | active |

Audit:

`systemctl status wg-quick@wg0`
`systemctl status docker`

Invariante:

WireGuard startet vor Caddy (implizit via Routing).

Audit-Lücke:
	•	Unit-Abhängigkeiten nicht dokumentiert.

---

## 8. Drift-Matrix

| Symptom | Ursache |
|---|---|
| NXDOMAIN fritz.box | Forwarding fehlt |
| 404 von Caddy | Host-Mismatch |
| no peer certificate | TLS Block fehlt |
| WG Handshake OK, kein Traffic | NAT fehlt |
| DNS geht, HTTP nicht | Routing |
| Server: cloudflare Header | Drift (Tunnel aktiv statt lokal) |

Invariante:

Jede Schicht testbar isoliert.

---

## 9. Crash-Recovery-Protokoll

### 9.1 Caddy Crashloop

Symptom:

`unrecognized directive`

Vorgehen:

```bash
docker logs edge-caddy
caddy validate --config /etc/caddy/Caddyfile
docker compose up -d --force-recreate
```

Invariante:

Caddyfile immer syntaktisch validieren vor Restart.

---

### 9.2 DNS Totalausfall

Test:

`dig google.com @127.0.0.1`

Wenn tot:

`docker restart dns-pihole`


---

### 9.3 VPN kein Zugriff auf LAN

Check:

`sudo wg show`
`sudo iptables -t nat -S`

Fehlt:

`MASQUERADE`

→ hinzufügen.

---

## 10. Sicherheits-Invarianten
	1.	Kein öffentliches Exposing von Pi-hole UI
	2.	Kein Full-Tunnel ohne Absicht
	3.	Kein externer DNS Forward für home.arpa
	4.	Caddy nur intern TLS
	5.	Fritzbox DHCP DNS → Pi-hole


Audit-Offene Punkte
	•   rp_filter Status
	• 	nftables Konsistenz
	•	IPv6 Strategie dokumentiert? (Status: IPv6 Listeners auf 80/443/53 aktiv)
	•	Docker published Ports review (siehe 5.3)
	•	UFW aktiv oder nicht? (Status: iptables-nft aktiv)
	•   UFW Status nicht dokumentiert
	•	IPv6 Policy unklar
	•	Docker rootless vs root nicht dokumentiert

Empfohlen zusätzlich loggen:

```bash
sudo ufw status
sudo sysctl -a | grep ipv6
docker info
```

Optional:
	•	`nft list ruleset`
	•	`ip6tables -S`

---

## 11. Hardware Snapshot – 2026-02-18

**RAM Upgrade**

*   **Installed RAM:** 2x 16GB DDR4-3200 SO-DIMM
*   **Total:** 32GB
*   **Configured Speed:** 3200 MT/s
*   **Voltage:** 1.2V

**Verification:**

*   `free -h`: `Mem: 30Gi total` (GiB vs GB + reserved)
*   `dmidecode`: 2x 16GB, 3200 MT/s, 1.2V

---

## 12. Runtime-Definition

Heimserver Runtime ist kohärent, wenn:
	•	DNS → Pi-hole
	•	fritz.box forward korrekt
	•	WG → NAT korrekt
	•	Caddy → home.arpa only
	•	TLS → internal CA trusted

Alles andere ist Drift.

---

## Essenz

Heimserver Runtime ist stabil, wenn:
	•	WG korrekt NATed
	•	DNS nicht splitbrain
	•	Caddy nur auf home.arpa hört
	•	Kein Full-Tunnel ohne Absicht

Heimserver ist kein Server.

Er ist ein:
	•	DNS-Knoten
	•	VPN-Pivot
	•	Reverse-Proxy-Grenzpunkt
	•	Vertrauensträger

Wenn eine dieser Achsen bricht, bricht Kohärenz.

---

Unsicherheitsgrad: 0.12
Ursache: IPv6 und Firewall-Policy nicht vollständig erfasst.

Interpolationsgrad: 0.18
Annahmen: Keine weitere NAT- oder Reverse-Proxy-Schicht vorgeschaltet.
