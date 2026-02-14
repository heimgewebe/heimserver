# heimserver.naming.md

Kanonische Namens- und Adressierungsarchitektur
⛔️ ARCHITEKTURDOKUMENT · NICHT ÖFFENTLICH

Stand: 2026-02-13
Scope: Heimserver + Heimgewebe + Weltgewebe

---

## 1. Namensphilosophie

These: Namen sind nur Labels.
Antithese: Namen bestimmen Systemverhalten.
Synthese: Namen sind Routing-Anweisungen mit semantischer Ladung.

Destabilisierung:
Das Problem war nicht „kein Zugriff“.
Das Problem war „inkohärente Namensräume“.

Wenn DNS, TLS, Caddy und WireGuard unterschiedliche Realitäten kennen, entsteht Splitbrain.

---

## 2. Root-Zone (KANONISCH)

Primäre interne Root

`home.arpa`

Begründung:
	•	RFC 8375 reserviert für Heimnetze
	•	kollisionsfrei
	•	nicht öffentlich delegiert
	•	sauber für interne PKI

Verboten:

| Zone | Grund |
|---|---|
| `.local` | mDNS-Konflikt |
| `.home` | nicht reserviert |
| `.lan` | unspezifiziert |
| `.internal` | potentiell öffentlich kollidierend |

---

## 3. Subzonen (Strikte Trennung)

### 3.1 Heimgewebe

`heimgewebe.home.arpa`

Semantik:
	•	Heimnetz
	•	Heimgewebe als Systemverbund
	•	Leitstand, Haussteuerung, Observatorium

### 3.2 Weltgewebe

`weltgewebe.home.arpa`

Semantik:
	•	Externe Welt-Simulation / Weltgewebe-Services
	•	API-Backends für Weltgewebe
	•	Getrennter Kontext vom Heimnetz

**Policy:**
Keine Kreuzung.
Heimgewebe-Dienste heißen `*.heimgewebe...`
Weltgewebe-Dienste heißen `*.weltgewebe...`

---

## 4. FQDN-Struktur

### 4.1 Heimgewebe

Leitstand

`leitstand.heimgewebe.home.arpa`

API

`api.heimgewebe.home.arpa`

Root-Alias (optional)

`heimgewebe.home.arpa`

### 4.2 Weltgewebe

Root-Alias (optional)

`weltgewebe.home.arpa`

API

`api.weltgewebe.home.arpa` (sofern existent)

**Regel:**
Keine Kurzformen.
Keine alternativen Domains.
Keine parallelen Namensräume.

Ein Host → ein kanonischer Name.

---

## 5. TLS-Policy

Caddy `tls internal`.

Konsequenz:
	•	Eigene lokale CA
	•	Root-Zertifikat muss auf Clients installiert werden
	•	Kein öffentliches ACME

Nicht erlaubt:
	•	Mischbetrieb öffentlich + intern für dieselbe Zone
	•	parallele Zertifikate mit anderem CN

---

## 6. Caddy-Namensbindung

Jeder Hostblock entspricht exakt einem FQDN.

Beispiel Heimgewebe:

```
http://leitstand.heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://leitstand.heimgewebe.home.arpa {
  reverse_proxy deploy-leitstand-1:3000
  tls internal
}
```

Beispiel Weltgewebe:

```
https://api.weltgewebe.home.arpa {
  reverse_proxy weltgewebe-api:8080
  tls internal
}
```

Kein Catch-All für interne Hosts.
Kein „Shared Host“ für beide Zonen.

---

## 7. DNS-Kanon

Pi-hole `/etc/dnsmasq.d/99-heimgewebe.conf`:

```
address=/leitstand.heimgewebe.home.arpa/192.168.178.46
address=/api.heimgewebe.home.arpa/192.168.178.46
address=/heimgewebe.home.arpa/192.168.178.46
```

Pi-hole `/etc/dnsmasq.d/99-weltgewebe.conf`:

```
address=/weltgewebe.home.arpa/192.168.178.46
address=/api.weltgewebe.home.arpa/192.168.178.46
```

Keine:
	•	`local=/home.arpa/`
	•	host-record + address Mischung
	•	`custom.list` Duplikate

Nur EIN Mechanismus.

---

## 8. Client-Sicht

Alle Clients sehen:

`leitstand.heimgewebe.home.arpa` → `192.168.178.46`
`api.weltgewebe.home.arpa` → `192.168.178.46`

Egal ob:
	•	LAN
	•	WireGuard
	•	Split-Tunnel
	•	Full-Tunnel

DNS-Quelle ist immer Pi-hole.

---

## 9. Verbotene Drift-Muster

| Drift | Effekt |
|---|---|
| paralleles `leitstand.home` | falsches Zertifikat |
| mehrere FQDNs auf denselben Host | TLS-Konflikt |
| Router-DNS ≠ Pi-hole | Splitbrain |
| Private Relay aktiv | DNS-Umgehung |
| Heimgewebe-Host auf Weltgewebe-Upstream | Semantischer Bruch |


---

## 10. Semantische Invarianten
	1.	Ein Dienst = ein kanonischer FQDN
	2.	Ein FQDN = eine DNS-Antwort
	3.	Eine DNS-Antwort = eine IP
	4.	Eine IP = ein Entry-Proxy

Kein Multi-Truth.

---

## 11. Zukunftsregeln

Wenn neue Dienste entstehen:

`<dienst>.heimgewebe.home.arpa` oder `<dienst>.weltgewebe.home.arpa`

Beispiele:

`chronik.heimgewebe.home.arpa`
`simulator.weltgewebe.home.arpa`

Keine Sub-Sub-Domains ohne Not.

---

## 12. Essenz

Namensräume sind Machtstrukturen.

Wer mehrere Namen zulässt,
verliert Wahrheit.

Ein System mit einem Namen
ist kohärent.

---

## Risikoanalyse

Hoch:
	•	parallele Domains
	•	öffentlich delegierte TLD
	•	DNS-Forwarding außerhalb Pi-hole

Mittel:
	•	IPv6-Namensauflösung
	•	Zertifikats-Drift bei CA-Erneuerung

Gering:
	•	einzelne Record-Anpassung

---

## Unsicherheitsgrad

0.10

Ursachen:
	•	IPv6 AAAA-Records nicht systematisch konfiguriert
	•	keine formale DNSSEC-Policy intern
	•	kein dedizierter Resolver-Testautomatismus

Interpolationsgrad:
0.05

Annahmen:
	•	keine weiteren internen Subzones
	•	keine Hybrid-Cloud-Integration
