---
id: ops-runbook-heimserver-edge
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: Heimserver Edge Runbook
summary: Operations for Heimserver Edge gateway
last_reviewed: 2026-03-11
depends_on:
  - architecture/network.md
  - architecture/networking/port-matrix.md
---

# Heimserver-Edge-Dokumentation (Netzwerk, Gateway, Container)

Dieses Runbook dokumentiert die aktuelle **Heimserver-Architektur**, die als Edge-Knoten für das Weltgewebe dient.

Der Server übernimmt folgende Rollen:

* Edge-Gateway (Caddy)
* Container-Host (Docker Compose)
* DNS Resolver / Local DNS Server (Pi-hole)
* Weltgewebe-API-Host

Ziel ist eine reproduzierbare Dokumentation der Infrastruktur.

---

# Heimserver Überblick

Hostname

```
heimserver
```

Betriebssystem

```
Ubuntu Server
```

Lokale IP

```
192.168.178.46
```

Netzwerkinterface

```
eno2
```

WireGuard

```
wg0
```

---

# Edge Gateway Architektur

Der Heimserver verwendet ein Edge-Gateway-Modell.

Gateway-Container

```
edge-caddy
```

Image

```
caddy:2.x
```

Ports

```
80
443
```

Routing

```
weltgewebe.net
api.weltgewebe.net
```

Caddy übernimmt:

* TLS-Zertifikate
* HTTPS-Redirect
* Reverse-Proxy

---

# Container-Stacks

Die Infrastruktur ist in zwei getrennte Compose-Projekte aufgeteilt, um die Frontdoor sauber vom App-Stack zu isolieren.

## Edge-Stack (Frontdoor)

Docker Compose Projekt

```
edge
```

Container:

| Service    | Port     | Funktion             |
| ---------- | -------- | -------------------- |
| edge-caddy | 80 / 443 | Gateway, TLS, Reverse Proxy |

Das Routing läuft über den Edge-Stack als zentrales Gateway zum dahinterliegenden Weltgewebe-App-Stack.

## Weltgewebe-Stack (App-Stack)

Docker Compose Projekt

```
weltgewebe
```

Container:

| Service    | Port     | Funktion       |
| ---------- | -------- | -------------- |
| api        | 8080     | Weltgewebe API |
| db         | 5432     | PostgreSQL     |
| nats       | 4222     | Messaging      |

*(Hinweis: Die Container des Weltgewebe-Stacks (`api`, `db`, `nats`) binden **keine** Host-Ports. Siehe `architecture/networking/port-matrix.md`)*

---

# Lokale Dienste

Weitere Dienste auf dem Host:

```
pihole-FTL
```

Port

```
8081
```

Funktion

```
DNS / Adblocking
```

---

# Netzwerkstruktur

Internet

↓

Router (FritzBox)

↓

Portforward

```
80
443
```

↓

Heimserver

↓

Edge-Caddy

↓

Container

---

# DNS Bezug

Domain

```
weltgewebe.net
```

DNS Provider

```
IONOS
```

Nameserver

```
ns1121.ui-dns.com
ns1044.ui-dns.org
ns1086.ui-dns.biz
ns1036.ui-dns.de
```

Records

```
A weltgewebe.net → Public IP
A api.weltgewebe.net → Public IP
```

Mail

```
MX mx00.ionos.de
MX mx01.ionos.de
```

---

# Diagnosebefehle

## öffentliche IP

```bash
curl ifconfig.me
```

## DNS

```bash
dig A weltgewebe.net
dig MX weltgewebe.net
```

## offene Ports

```bash
ss -tulpn
```

## Container

Für den **Edge-Stack**:

```bash
cd /opt/heimgewebe/edge
docker compose ps
```

Für den **Weltgewebe-Stack**:

```bash
cd /opt/weltgewebe
docker compose -p weltgewebe ps
```

Schneller Reality-Check (Gateway):

```bash
docker ps | grep caddy
```

## Gateway Test

```bash
curl -I http://weltgewebe.net
```

Expected

```
308 Permanent Redirect
Server: Caddy
```

---

# Typische Incident-Ursachen

## Router blockiert Ports

Symptom

```
curl <public-ip>
connection refused
```

Lösung

```
Portfreigabe 80 / 443 prüfen
```

---

## Hairpin NAT / Host-Header Fallstrick

Symptom

Lokale Tests gegen die Public IP schlagen fehl.

Beispiel

```bash
curl http://149.xxx.xxx.xxx
```

Wichtiger Hinweis:
Dieser Test kann aus zwei Gründen fehlschlagen:
1. **Hairpin NAT / NAT-Loopback** im Router funktioniert nicht.
2. **vHost-Mismatch:** Caddy erwartet als Host-Header `weltgewebe.net` oder `api.weltgewebe.net` und nicht die nackte IP. Ein lokaler Request gegen die IP beweist also nicht zwingend eine kaputte Portfreigabe.

Korrekte Gegenproben:

Domain testen:
```bash
curl -I http://weltgewebe.net
```

Host-Header explizit setzen:
```bash
curl -H "Host: weltgewebe.net" http://149.xxx.xxx.xxx
```

Am aussagekräftigsten ist es immer, **extern** (z. B. über das Mobilfunknetz) zu testen.

---

## falsche DNS Authority

Symptom

```bash
dig NS weltgewebe.net
```

zeigt falsche Nameserver.

Lösung

DNS Migration prüfen.

---

# Validierungszustand

Öffentliche Tests erfolgreich:

```bash
curl -I http://weltgewebe.net
```

Ergebnis

```
HTTP 308
Server: Caddy
```

DNS:

```bash
dig A weltgewebe.net
```

zeigt öffentliche IP.

---

# Architekturprinzip

Der Heimserver fungiert als:

```
Edge Node
```

für das Weltgewebe.

Seine Aufgaben:

* Gateway
* Service Host
* lokaler Infrastrukturknoten

---

# Motivation

Ohne diese Dokumentation entstehen typische Probleme erneut:

* DNS zeigt korrekt, aber Router blockiert
* Caddy läuft, aber Container nicht
* lokale NAT-Fehldiagnosen

Das Runbook reduziert Debug-Zeit.

---

# Typische Fehlannahme

Fehlerhafte Annahme:

> „Docker läuft → Server erreichbar.“

Realität:

```
Internet → Router → Gateway → Container
```

Alle vier Ebenen müssen funktionieren.

---

# Essenz

Der Heimserver ist jetzt dokumentiert als:

```
Edge-Knoten des Weltgewebes
```

Architektur:

```
DNS
↓
Router
↓
edge-caddy
↓
Container
```

Dieses Runbook macht aus implizitem Wissen eine reproduzierbare Infrastruktur.
