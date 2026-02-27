# network.md

Kanonische Netz- und Transportarchitektur
⛔️ ENTHÄLT SICHERHEITSRELEVANTE STRUKTUR
⛔️ NICHT VERÖFFENTLICHEN

Stand: 2026-02-13
Host: heimserver
Dokumentklasse: ARCHITEKTUR · KANONISCH

**Sicherheits-Policy (Repo-Status):**
Dieses Dokument enthält sicherheitsrelevante Strukturen.
Falls das Repo entgegen der Policy public wird (Security Incident), ist eine sofortige Redaction von IPs, Subnetzen und Keys zwingend erforderlich.

---

## 1. Netzphilosophie

These: Ein Heimserver ist nur so stabil wie sein Routing.
Antithese: Routing ist Nebensache, Dienste sind entscheidend.
Synthese: Dienste ohne saubere Transportlogik erzeugen Geisterfehler.

Destabilisierung:
Das Problem war nie „DNS kaputt“.
Das Problem war „Splitbrain durch falsche AllowedIPs“.

---

## 2. Netzsegmente (Ist-Zustand)

### 2.1 LAN

Subnetz: `192.168.178.0/24`
Gateway: `192.168.178.1` (Fritzbox)
Server-IP: `192.168.178.46`

Rolle:
	•	Primärtransport für Heimgeräte
	•	DNS-Ziel für Clients
	•	Reverse-Proxy-Entry

---

### 2.2 WireGuard (Remote-Zugang)

Interface: `wg0`
Server-IP: `10.7.0.1/24`
Peer (iPad): `10.7.0.2/32`
Port: `51820/udp`

Routingziel:
	•	LAN
	•	Internet optional (Split-Tunnel konfiguriert)

Wichtige Invariante:
AllowedIPs auf Serverseite darf nur Peer-IP enthalten:

`AllowedIPs = 10.7.0.2/32`

NICHT:

`AllowedIPs = 192.168.178.0/24`

Das erzeugt asymmetrisches Routing.

---

## 3. Routing-Topologie

```
iPad (10.7.0.2)
   ↓
wg0 (10.7.0.1)
   ↓
heimserver
   ↓
LAN (192.168.178.0/24)
```

Server:
`net.ipv4.ip_forward = 1`

NAT:

`iptables -t nat -A POSTROUTING -s 10.7.0.0/24 -o eno2 -j MASQUERADE`


---

## 4. DNS-Architektur

### 4.1 Pi-hole

Läuft auf:
`192.168.178.46:53`

Container-Modus:
NetworkMode: host

Wichtig:
`etc_dnsmasq_d = true` in `pihole.toml`

---

### 4.2 Interne Zone

Root:
`home.arpa`

Subzone:
`heimgewebe.home.arpa`

Records:

`leitstand.heimgewebe.home.arpa`
`api.heimgewebe.home.arpa`
`heimgewebe.home.arpa`

Kein `.home`
Kein `.local`
Kein `.lan`

Nur `.home.arpa`.

---

## 5. Fritzbox-Integration (empfohlen)

These: Client-DNS manuell setzen
Antithese: Router-DNS setzen
Synthese: Router-DNS ist stabiler

Empfehlung:
Fritzbox → Heimnetz → Netzwerk → Netzwerkeinstellungen
Lokaler DNS-Server = `192.168.178.46`

Dann:
Clients auf „Automatisch“

Kein Split-DNS
Kein Client-Drift
Keine iOS-Sonderfälle

---

## 6. Split-Tunnel-Policy (iPad)

AllowedIPs im iPad:

`10.7.0.0/24`
`192.168.178.0/24`

Optional:

`0.0.0.0/0`

DNS im WG-Profil:

`192.168.178.46`

Private Relay:
**aus**

Sonst umgeht Apple das lokale DNS.

---

## 7. Docker-Netze

Docker-Bridge-Netze:
	•	`172.18.0.0/16`
	•	`172.19.0.0/16`
	•	weitere interne Netze

Vertrauensstufe:
intern, aber nicht gleich LAN

Caddy hängt in:
	•	`edge`
	•	`heimnet`

### 7.1 Port-Ownership & Host-Netz (Invariante)

Siehe: [`networking/port-matrix.md`](networking/port-matrix.md)

*   **Ports 80/443:** Exklusiv Edge-Gateway (Caddy) [TCP, UDP optional].
*   **Port 53:** `dns-pihole` (Host-Mode).
*   **Port 8081:** `dns-pihole` Webinterface (Reserviert).
*   **Apps (API/DB):** Internal only (keine Host-Ports).

---

## 8. Test-Matrix (KANONISCH)

DNS

`dig +short leitstand.heimgewebe.home.arpa @192.168.178.46`

Erwartung:
`192.168.178.46`

---

Host-Match

`curl -I http://192.168.178.46 -H 'Host: leitstand.heimgewebe.home.arpa'`

Erwartung:
`308 Redirect`

---

HTTPS

`curl -k https://leitstand.heimgewebe.home.arpa`

Erwartung:
`200`

---

WireGuard Verkehr prüfen

`tcpdump -i wg0 port 53 or port 80 or port 443`

Wenn DNS auf 192.168.178.1 geht → Split-Tunnel falsch.

---

## 9. Typische Fehlannahmen (korrigiert)

| Fehlannahme | Realität |
|---|---|
| DNS-Problem. | Routing-Problem. |
| Caddy kaputt. | Falscher Host im Container. |
| Pi-hole reagiert nicht. | `etc_dnsmasq_d = false`. |

---

## 10. Drift-Indikatoren

Neubewertung zwingend bei:
	•	WG-Peer Änderung
	•	AllowedIPs Änderung
	•	Fritzbox DNS Änderung
	•	Docker Netzwerk-Neudefinition
	•	Pi-hole Update

---

## 11. Verdichtete Essenz

Routing ist Wahrheit.
DNS ist nur Semantik.
Wenn Pakete falsch laufen, helfen keine Logs.

Heimgewebe scheitert nicht an Software.
Es scheitert an falsch gesetzten Bits.

---

## Risikoanalyse

Hoch:
	•	falsche AllowedIPs
	•	Fritzbox-DNS-Drift
	•	Private Relay aktiv

Mittel:
	•	Docker-Netz-Overlap
	•	IPv6 nicht berücksichtigt

Gering:
	•	DNS-Record-Fehler

---

## Unsicherheitsanalyse

Unsicherheitsgrad: 0.12

Ursachen:
	•	IPv6-Routing nicht vollständig dokumentiert
	•	Fritzbox-UI-Drift möglich
	•	Docker-nftables-Interaktion nicht explizit geprüft

Interpolationsgrad: 0.07

Annahmen:
	•	keine zusätzlichen statischen Routen
	•	keine parallelen VPN-Profile auf iPad

Systembedingt:
	•	Mobilfunk NAT-Wechsel
