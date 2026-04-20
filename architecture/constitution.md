---
id: constitution
role: norm
status: active
canonicality: canonical
doc_type: architecture
title: Heimserver Constitution
summary: Canonical rules and context for Heimserver
last_reviewed: 2026-02-13
depends_on: []
verifies_with:
  - ops/checks/preflight.sh
---

# constitution.md

Version 4.0 · Konsolidierte Verfassung
Stand: 2026-02-13
Host: heimserver
Dokumentklasse: ARCHITEKTUR · KANONISCH

## 0. Identität & Zweck

Der Heimserver ist der Trust-Pivot des Heimgewebes.
Er ist kein öffentlicher Server, sondern ein kontrollierter Binnenraum.
Er vereint Identität, Routing und Namensauflösung in einer kohärenten Runtime.

Hinweis: Bestimmte Deployments (z.B. Weltgewebe/Leitstand/API) laufen aktuell nur für die Entwicklungs- und Integrationsphase auf diesem Heimserver und können später migrieren; die Sicherheits- und Kohärenzprinzipien bleiben unverändert.

**Scope:**
Dieses Dokument definiert die unverhandelbaren Grundsätze (Verfassung).
Details befinden sich in den spezifischen Kanon-Dokumenten.

---

## 1. Kanon-Struktur (Zuständigkeit)

Die Wahrheit ist föderal organisiert:

*Hinweis: Siehe `heimnetz-2026.md` für die geplante Zielarchitektur.*

| Dokument | Zuständigkeit | Inhalt |
|---|---|---|
| [`constitution.md`](constitution.md) (dieses) | Verfassung | Zweck, Verbote, Drift-Trigger |
| [`heimnetz-2026.md`](heimnetz-2026.md) | Zielarchitektur | Blueprint für Determinismus & Ebenentrennung |
| [`runtime.md`](../runtime/runtime.md) | Realität | Aktuelle Ports, IPs, Container |
| [`network.md`](network.md) | Transport | Routing, NAT, WireGuard, Firewall |
| [`naming.md`](naming.md) | Semantik | DNS-Zonen, TLS, Hostnames |
| [`operations.md`](../operations/operations.md) | Handeln | Checks, Wiederherstellung, Backups |

---

## 2. Hard Rules (Unverhandelbare Verbote)

1. **Kein Public Exposing**
   Dienste dürfen niemals direkt ins Internet exponiert werden (kein Port-Forwarding im Router).
   Einziger Ingress ist WireGuard oder der Reverse Proxy (intern).

   *Architektur-Entscheidung:*
   Dienste (Docker/Caddy) dürfen auf 0.0.0.0 lauschen.
   Sicherheit wird NICHT durch Loopback-Binding, sondern durch Firewall-Regeln (DOCKER-USER Chain) erzwungen.
   Offene Listener sind zulässig, solange DOCKER-USER die Exposition begrenzt; runtime dokumentiert Listener, preflight/iptables dokumentieren die Erreichbarkeit.

2. **Kein Host-Caddy**
   Caddy läuft ausschließlich als Docker-Container. Systemd-Caddy ist verboten.

3. **Kein Caddy Admin Exposing**
   Der Admin-Port (2019) darf niemals lauschen (außer localhost innerhalb des Containers).

4. **QUIC-Policy**
   HTTP/3 (QUIC/UDP 443) ist standardmäßig AUS.
   Eine Aktivierung erfordert Dokumentation und `ALLOW_QUIC=1` im Preflight-Check.

5. **DNS-Souveränität**
   Die Zone `home.arpa` wird niemals an externe Resolver (8.8.8.8 etc.) weitergeleitet.
   Pi-hole ist die einzige Quelle der Wahrheit für interne Namen.

6. **Kein Splitbrain**
   Ein Hostname hat im gesamten Heimgewebe (LAN + WireGuard) genau eine IP.
   Split-Horizon-DNS ist zu vermeiden.

---

## 3. Drift-Trigger (Wann muss dokumentiert werden?)

Jede Änderung an folgenden Komponenten erfordert eine Aktualisierung der Kanon-Dokumente:

| Komponente | Dokument |
|---|---|
| Docker Container / Compose | [`runtime.md`](../runtime/runtime.md) |
| Firewall / iptables / NAT | [`network.md`](network.md) |
| WireGuard Peers / Routes | [`network.md`](network.md) |
| DNS Zonen / TLS Zertifikate | [`naming.md`](naming.md) |
| Backup-Strategie / Notfall | [`operations.md`](../operations/operations.md) |

**Pflege-Regel:**
Erst die Architektur klären (constitution/network/naming), dann die Runtime ändern (runtime), dann die Realität prüfen (operations).

---

## 4. Sicherheits-Invarianten (Guard)

Diese Invarianten werden durch `ops/checks/preflight.sh` überwacht:

1.	Port 80/443 sind vorhanden (Dienst läuft).
2.	Port 2019 ist tot (Sicherheit).
3.	Firewall (DOCKER-USER) erlaubt nur LAN (192.168.178.0/24) und WireGuard (10.7.0.0/24). Alles andere wird verworfen.

---

## 5. Essenz

Architektur ist das, was stabil bleibt, wenn man den Stecker zieht.
Runtime ist das, was passiert, wenn man ihn wieder einsteckt.
Drift ist der Unterschied zwischen beiden.

Dieses Repository minimiert Drift.
