Kanonischer operativer System-, Netzwerk- und Architekturkontext

⛔️ ENTHÄLT SICHERHEITSRELEVANTEN KONTEXT
⛔️ NICHT VERÖFFENTLICHEN
⛔️ Repo-Policy:
  - Repo privat halten
  - keine Logs, Snapshots, Schlüssel oder Exporte committen

Stand: 2026-02-12
Host: heimserver
Modus: produktiv, Clean-Reset validiert
Primärer Nutzer: alex
Dokumentklasse: OPERATIV · KANONISCH

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

3. Netzwerk – auditierter Ist-Zustand

Interfaces

Loopback
	•	127.0.0.1/8
	•	::1/128

LAN
	•	eno2: 192.168.178.46/24

WireGuard
	•	wg0: 10.7.0.1/24

IPv6
	•	Nur link-local (fe80::)
	•	Keine globale IPv6-Exposition

Docker-Netze (nicht vertrauenswürdig)
	•	docker0: 172.17.0.0/16 (derzeit DOWN)
	•	br-*: 172.18.0.0/16 (aktiv)
	•	veth*: Container-Links (link-local)

⸻

4. Vertrauenszonen (KANONISCH)

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

5. WireGuard – Transport-Layer

Server (heimserver)

Interface: wg0
Address: 10.7.0.1/24
ListenPort: 51820/udp
PrivateKey: nur lokal gespeichert

Peers

iPad
	•	Address: 10.7.0.2/32
	•	AllowedIPs:
	•	10.7.0.0/24
	•	192.168.178.0/24
	•	PersistentKeepalive: 25

Status:
	•	Handshake aktiv
	•	RX/TX vorhanden
	•	Latenz unauffällig

⸻

6. Architekturgrundsatz (KANONISCH)

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

7. Firewall – KANONISCHER IST-ZUSTAND

Firewall-Stack
	•	iptables-nft (KANONISCH)
	•	netfilter-persistent (Persistenz)
	•	Backend: nftables

Policy:
	•	filter: ACCEPT (Default)
	•	Explizite Regeln für Inbound Traffic

Explizite Regeln (Auszug):
	•	iifname "eno2" tcp/udp dport 53 accept
	•	iifname "wg0" tcp/udp dport 53 accept
	•	SSH (22): via Policy ACCEPT (LAN/WG Zugang)

NAT:
	•	Masquerade: 10.7.0.0/24 → eno2
	•	Docker-managed chains aktiv

IPv6 Filter:
	•	Policy ACCEPT (Kein restriktives IPv6-Regime)

Persistenzstatus (belegt)
	•	netfilter-persistent aktiv
	•	iptables Regeln persistent gespeichert
	•	nft Ruleset via iptables-nft verwaltet

⸻

8. Routing / Forwarding (WireGuard → LAN)

Status:
	•	IP-Forwarding aktiv (net.ipv4.ip_forward = 1)
	•	Aktuell keine expliziten FORWARD-Regeln notwendig

Hinweis (Kernel-Filter/Asymmetrie)
	•	rp_filter ist auf 2 (loose) gesetzt (all/default)

⸻

9. Docker & Firewall-Käfig (KANONISCH)

Docker ist aktiv, aber nicht vertrauenswürdig.

Regeln:
	•	keine Container-Ports nach WAN
	•	Reverse Proxy ist einziger Eintrittspunkt
	•	zusätzliche Absicherung über DOCKER-USER Chain

⸻

10. DOCKER-USER Chain – Umsetzung & Persistenz

Status:
	•	aktiv
	•	persistent (netfilter-persistent)
	•	auditfest

Regeln (KANONISCH):
	•	ACCEPT TCP 80/443 aus:
	•	192.168.178.0/24
	•	10.7.0.0/24
	•	DROP sonst für 80/443
	•	RETURN für nicht relevante Pakete

⸻

11. Reverse Proxy (Caddy)

Implementierung: Caddy (Docker)
Rolle: Entry-Gateway

Status:
	•	Docker-Caddy ist kanonisch
	•	Host-Caddy (systemd) ist verboten

Caddy-Admin:
	•	kein Publish
	•	keine Host-Exposition

TLS:
	•	internal CA

Sichtbarkeit:
	•	ausschließlich LAN + WireGuard

Explizite Verbote (Caddy)
	•	Caddy-Admin-Port (2019/tcp) darf niemals aus LAN,
		WireGuard oder WAN erreichbar sein
	•	HTTP/3 / QUIC (443/udp) ist nur erlaubt, wenn bewusst
		benötigt und explizit dokumentiert
	•	Default-Bind an 0.0.0.0 ist verboten

⸻

12. Docker-Caddy: Publish-Matrix (IST)

IST-Snapshot:
	•	80/tcp  → 127.0.0.1
	•	443/tcp → 127.0.0.1
	•	kein 443/udp
	•	kein 2019/tcp

Status:
loopback-gekäfigt, kein Admin-Port, kein QUIC

⸻

13. Aktive Listener (Host-Sicht)

Port	Service	Scope
22	sshd	0.0.0.0 + ::
53	pihole-FTL	0.0.0.0 + ::
5335	docker-proxy (unbound)	127.0.0.1
80	docker-proxy	öffentlich LAN
443	docker-proxy	öffentlich LAN

Eigentümer Port 53:
→ ausschließlich pihole-FTL

⸻

14. Audit-Pflichtprüfungen (KANONISCH)

Bei jeder Änderung an Docker, Compose, Firewall, Ports
oder Reverse Proxy müssen folgende Checks ausgeführt werden:
	•	docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep caddy
	•	ss -lntup | egrep '(:80|:443|:2019)\b'
	•	iptables -S DOCKER-USER
	•	sysctl net.ipv4.ip_forward
	•	wg show

Abweichungen vom dokumentierten IST gelten als Drift.

Belegpfad (außerhalb des Repos):
	•	/home/alex/server-facts/audit-snapshots/<timestamp>/

⸻

15. Weltgewebe-Caddy (bestehende Site)

Aktive Routen:
	•	/api/*        → api:8080
	•	/health/*     → api:8080
	•	/health/proxy → respond 200
	•	/             → externer Web-Upstream (Cloudflare / Vercel)

Diese Site bleibt unverändert.

⸻

16. Leitstand – Zielintegration

Rolle:
	•	permanenter Beobachtungsraum
	•	Viewer first, Actor second

Ziel-URL:
https://leitstand.lan

Status:
	•	Compose-Service geplant
	•	Zugriff ausschließlich über Caddy

⸻

17. ACS – Zielintegration

Rolle:
	•	Operations-Interface
	•	kontrollierter Actor

Status:
	•	Compose-Service geplant
	•	Zugriff nur via leitstand.lan/acs/
	•	kein Direktzugriff

⸻

18. Leitstand – Zugriffs- und Aktionspolicy

Standardmodus:
	•	READ-ONLY

Aktionen:
	•	ausschließlich über ACS
	•	keine impliziten Übergänge
	•	keine Fallback-Pfade vom Leitstand zu Write-Operationen

⸻

19. code-server (VS Code Web)

Bindung:
	•	127.0.0.1:8080

Zugriff:
	•	ausschließlich via SSH LocalForward
	•	kein Reverse Proxy
	•	kein TLS

Architekturentscheidung:
code-server bleibt Host-Service und wird nicht in Compose integriert.

⸻

20. Jules

Jules ist CLI/TUI-only.
	•	kein Webserver
	•	keine Ports
	•	keine Bindings

Typischer Workflow:
	•	jules new
	•	jules remote list --session
	•	jules remote pull --session --apply

⸻

21. Docker DNS-Stack (Unbound + Pi-hole)

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

22. Interne Namensauflösung (KANONISCH)

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

23. Firewall-Strategie – Entscheidung

Entscheidung:
iptables bleibt kanonisch (via nft backend).

Begründung:
	•	stabil
	•	transparent
	•	umgesetzt
	•	auditierbar

⸻

24. Service-Orchestrierung – Kanonische Regel

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

25. Kritische Persistenz (Hinweis)

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

26. Drift-Regel (bindend)

Jede Änderung an:
	•	Firewall
	•	Routing
	•	Ports
	•	Proxies
	•	Services

→ Pflicht zur Aktualisierung dieser Datei.

Drift-Trigger (bindend)
Eine Neubewertung dieses Dokuments ist zwingend, wenn:
	•	Änderung an docker-compose.yml
	•	Hinzufügen oder Entfernen eines published Ports
	•	Änderung an iptables / netfilter-persistent
	•	Wechsel des Docker-Backends
	•	Aktivierung von HTTP/3 oder TLS-Optionen in Caddy
	•	Änderung der DNS-Quelle

Versionshoheit
Dieses Dokument ersetzt alle früheren Versionen.

⸻

27. Verdichtete Essenz

Der Dienst bleibt lokal.
Der Zugriff reist.
Der Proxy vermittelt.
Die Wahrheit steht hier.

Entscheidende Lehre (2026-02-12):
Firewall-Härtung ohne Baseline-Definition erzeugt Self-Lockout-Risiko.
Service → Netzwerk → Security → Persistenz.
Nicht umgekehrt.

⸻

28. Ungewissheitsursachenanalyse

Unsicherheitsgrad: 0.16
Ursache:
	•	Router-Konfiguration nicht einsehbar
	•	Kein vollständiger Persistenz-Dump

Interpolationsgrad: 0.11
Annahme:
	•	Keine WAN-Portfreigaben aktiv
	•	Fritzbox verteilt 192.168.178.46 als DNS

Gesamtrisiko:
mittel-niedrig (kein WAN-Portforwarding angenommen)

────────────────────────────────────────────────────────────
ENDE DER KANONISCHEN DATEI
────────────────────────────────────────────────────────────
