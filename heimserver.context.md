Kanonischer operativer System-, Netzwerk- und Architekturkontext

⛔️ ENTHÄLT SICHERHEITSRELEVANTEN KONTEXT
⛔️ NICHT VERÖFFENTLICHEN
⛔️ Repo-Policy:
  - Repo privat halten
  - keine Logs, Snapshots, Schlüssel oder Exporte committen

Stand: 2026-02-13
Host: heimserver
Modus: produktiv, Clean-Reset validiert
Primärer Nutzer: alex
Dokumentklasse: ARCHITEKTUR · KONTEXT

Hinweis: Der aktuelle Laufzeit-Status, Ports und Netzwerke werden in `heimserver.runtime.md` gepflegt.

────────────────────────────────────────────────────────────

1. Systemidentität

Hostname: heimserver
Hardware: Lenovo ThinkCentre M70q Gen 4
CPU: Intel i7-13700T (16C / 24T)
RAM: 16 GiB
Swap: 4 GiB
Storage: NVMe ~476 GB
Firmware/BIOS: M4VKT2AA

Rolle
	•	permanenter Heimserver
	•	Entwicklungs- und Orchestrierungsserver
	•	Träger des Heimgewebe-Organismus

⸻

2. Betriebssystem & Basissystem

OS: Ubuntu 24.04 LTS (nftables via iptables-nft Backend)
Kernel: 6.8.x (generic)
Init-System: systemd

Service-Ebenen:
	•	systemd (system)
	•	systemd --user (linger aktiv für alex)

Updates:
	•	unattended-upgrades aktiv

Zeitsynchronisation:
	•	systemd-timesyncd

DNS-Hoheit (Host):
	•	systemd-resolved: deaktiviert & gestoppt
	•	/etc/resolv.conf: nameserver 127.0.0.1
	•	Ziel: vollständige DNS-Kontrolle über Pi-hole

⸻

3. Vertrauenszonen (KANONISCH)

Vertrauenswürdig
	•	Loopback: 127.0.0.1/8
	•	LAN: 192.168.178.0/24
	•	WireGuard: 10.7.0.0/24

Nicht vertrauenswürdig
	•	Docker-Netze: 172.16.0.0/12
	•	WAN / Internet

Grundsatz:
Docker gilt explizit nicht als Vertrauenszone.

⸻

4. Architekturgrundsatz (KANONISCH)

Leitprinzipien
	•	Dienste bleiben lokal
	•	Zugriff reist (LAN + WireGuard)
	•	Transport vor Dienst
	•	Komfort folgt Sicherheit
	•	DNS-Isolation: gut

Zielbild

Heimserver-only mit strikt eingesperrtem Entry-Gateway.

Erlaubt
	•	Reverse Proxy als internes Gateway
	•	Erreichbar ausschließlich aus LAN und WireGuard
	•	Backends strikt lokal oder Compose-intern

Verboten
	•	öffentliche Webdienste
	•	Reverse Proxy ohne Firewall-Caging
	•	Backends auf 0.0.0.0
	•	temporäre Portöffnungen

Begründung:
Ein eingesperrter Reverse Proxy erhöht Komfort,
ohne die Angriffsfläche real zu vergrößern.

⸻

5. Weltgewebe-Caddy (bestehende Site)

Aktive Routen:
	•	/api/*        → api:8080
	•	/health/*     → api:8080
	•	/health/proxy → respond 200
	•	/             → externer Web-Upstream (Cloudflare / Vercel)

Diese Site bleibt unverändert.

⸻

6. Leitstand – Zielintegration

Rolle:
	•	permanenter Beobachtungsraum
	•	Viewer first, Actor second

Ziel-URL:
https://leitstand.lan

Status:
	•	Compose-Service geplant
	•	Zugriff ausschließlich über Caddy

⸻

7. ACS – Zielintegration

Rolle:
	•	Operations-Interface
	•	kontrollierter Actor

Status:
	•	Compose-Service geplant
	•	Zugriff nur via leitstand.lan/acs/
	•	kein Direktzugriff

⸻

8. Leitstand – Zugriffs- und Aktionspolicy

Standardmodus:
	•	READ-ONLY

Aktionen:
	•	ausschließlich über ACS
	•	keine impliziten Übergänge
	•	keine Fallback-Pfade vom Leitstand zu Write-Operationen

⸻

9. code-server (VS Code Web)

Bindung:
	•	127.0.0.1:8080

Zugriff:
	•	ausschließlich via SSH LocalForward
	•	kein Reverse Proxy
	•	kein TLS

Architekturentscheidung:
code-server bleibt Host-Service und wird nicht in Compose integriert.

⸻

10. Jules

Jules ist CLI/TUI-only.
	•	kein Webserver
	•	keine Ports
	•	keine Bindings

Typischer Workflow:
	•	jules new
	•	jules remote list --session
	•	jules remote pull --session --apply

⸻

11. Docker DNS-Stack (Unbound + Pi-hole)

Pfad: /opt/heimgewebe/dns/docker-compose.yml

Unbound (Rekursiver Resolver)
	•	Image: mvance/unbound:latest
	•	Container: dns-unbound
	•	Binding: 127.0.0.1:5335 (TCP/UDP)
	•	Rolle: Upstream für Pi-hole
	•	Isolation: nicht extern erreichbar

Pi-hole (Filter & Forwarder)
	•	Image: pihole/pihole:latest
	•	Container: dns-pihole
	•	Network Mode: host
	•	Listener: 0.0.0.0:53
	•	Upstream: 127.0.0.1#5335

Rolle:
DNS-Policy + Forwarder + Filter.

⸻

12. Interne Namensauflösung (KANONISCH)

Quelle:
	•	Pi-hole (192.168.178.46)

Status:
	•	Vollständige DNS-Kontrolle
	•	Wildcard-Support via *.heimgewebe.home.arpa

Funktionstests (Valide A-Records):
	•	DNS lokal: @127.0.0.1
	•	DNS LAN: @192.168.178.46
	•	DNS WireGuard: @10.7.0.1

Drift-Verbot:
	•	Keine Split-DNS-Konflikte
	•	Keine mDNS-Leaks

⸻

13. Firewall-Strategie – Entscheidung

Entscheidung:
iptables bleibt kanonisch (via nft backend).

Begründung:
	•	stabil
	•	transparent
	•	umgesetzt
	•	auditierbar

⸻

14. Service-Orchestrierung – Kanonische Regel

systemd:
	•	Transport
	•	Zugriff
	•	Host-nahe Dienste (z. B. SSH, WireGuard, code-server)

Docker / Compose:
	•	HTTP-/HTTPS-Dienste
	•	UIs
	•	APIs
	•	Proxies

Mischformen:
	•	verboten (Ausnahmen müssen explizit dokumentiert werden)

⸻

15. Kritische Persistenz (Hinweis)

Kritisch:
	•	WireGuard-Schlüssel
	•	iptables-Regeln (Persistenz via netfilter-persistent)
	•	Docker-Volumes (Caddy, Leitstand, ACS)
	•	Docker Auto-Start

Nicht kritisch:
	•	Container-Images
	•	temporäre Artefakte
	•	Logs ohne Audit-Relevanz

⸻

16. Verdichtete Essenz

Der Dienst bleibt lokal.
Der Zugriff reist.
Der Proxy vermittelt.
Die Wahrheit steht hier.

Entscheidende Lehre (2026-02-12):
Firewall-Härtung ohne Baseline-Definition erzeugt Self-Lockout-Risiko.
Service → Netzwerk → Security → Persistenz.
Nicht umgekehrt.
