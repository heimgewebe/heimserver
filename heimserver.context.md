heimserver.context.md

Version 4.0 · Konsolidierte Verfassung
Stand: 2026-02-13
Host: heimserver
Dokumentklasse: ARCHITEKTUR · KANONISCH

⸻

0. Identität & Zweck

Der Heimserver ist der Trust-Pivot des Heimgewebes.
Er ist kein öffentlicher Server, sondern ein kontrollierter Binnenraum.
Er vereint Identität, Routing und Namensauflösung in einer kohärenten Runtime.

Scope:
Dieses Dokument definiert die unverhandelbaren Grundsätze (Verfassung).
Details befinden sich in den spezifischen Kanon-Dokumenten.

⸻

1. Kanon-Struktur (Zuständigkeit)

Die Wahrheit ist föderal organisiert:

Dokument	Zuständigkeit	Inhalt
heimserver.context.md (dieses)	Verfassung	Zweck, Verbote, Drift-Trigger
heimserver.runtime.md	Realität	Aktuelle Ports, IPs, Container
heimserver.network.md	Transport	Routing, NAT, WireGuard, Firewall
heimserver.naming.md	Semantik	DNS-Zonen, TLS, Hostnames
heimserver.operations.md	Handeln	Checks, Wiederherstellung, Backups

⸻

2. Hard Rules (Unverhandelbare Verbote)

1. Kein Public Exposing
   Dienste dürfen niemals direkt ins Internet exponiert werden (kein Port-Forwarding im Router).
   Einziger Ingress ist WireGuard oder der Reverse Proxy (intern).

2. Kein Host-Caddy
   Caddy läuft ausschließlich als Docker-Container. Systemd-Caddy ist verboten.

3. Kein Caddy Admin Exposing
   Der Admin-Port (2019) darf niemals lauschen (außer localhost innerhalb des Containers).

4. DNS-Souveränität
   Die Zone `home.arpa` wird niemals an externe Resolver (8.8.8.8 etc.) weitergeleitet.
   Pi-hole ist die einzige Quelle der Wahrheit für interne Namen.

5. Kein Splitbrain
   Ein Hostname hat im gesamten Heimgewebe (LAN + WireGuard) genau eine IP.
   Split-Horizon-DNS ist zu vermeiden.

⸻

3. Drift-Trigger (Wann muss dokumentiert werden?)

Jede Änderung an folgenden Komponenten erfordert eine Aktualisierung der Kanon-Dokumente:

Komponente	Dokument
Docker Container / Compose	runtime.md
Firewall / iptables / NAT	network.md
WireGuard Peers / Routes	network.md
DNS Zonen / TLS Zertifikate	naming.md
Backup-Strategie / Notfall	operations.md

Pflege-Regel:
Erst die Architektur klären (context/network/naming), dann die Runtime ändern (runtime), dann die Realität prüfen (operations).

⸻

4. Sicherheits-Invarianten (Guard)

Diese Invarianten werden durch `ops/checks/preflight.sh` überwacht:

1.	Port 80/443 sind vorhanden (Dienst läuft).
2.	Port 2019 ist tot (Sicherheit).
3.	Firewall (DOCKER-USER) erlaubt nur LAN (192.168.178.0/24) und WireGuard (10.7.0.0/24). Alles andere wird verworfen.

⸻

5. Essenz

Architektur ist das, was stabil bleibt, wenn man den Stecker zieht.
Runtime ist das, was passiert, wenn man ihn wieder einsteckt.
Drift ist der Unterschied zwischen beiden.

Dieses Repository minimiert Drift.
