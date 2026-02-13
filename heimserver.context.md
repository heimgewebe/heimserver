heimserver.context.md

Version 3.0 · konsolidiert · kanonisch
Stand: 2026-02-13

⸻

0. Identität

Heimserver ist:
	•	physischer Host im LAN
	•	DNS-Autorität für *.home.arpa
	•	Reverse-Proxy-Gateway
	•	WireGuard-Ingress
	•	Heimgewebe-Runtime-Träger

Er ist kein Public-Server.
Er ist ein kontrollierter Binnenraum.

⸻

1. Systemkern

Host
	•	IP: 192.168.178.46
	•	Interface LAN: eno2
	•	Interface VPN: wg0
	•	OS: Ubuntu
	•	Docker Runtime aktiv

⸻

Docker-Netze
	•	heimnet (interne Servicekommunikation)
	•	edge (Caddy Gateway)
	•	weitere isolierte Bridge-Netze

⸻

2. DNS-Architektur

Autorität

Pi-hole (FTL) läuft im Host-Netz (network_mode: host).

Wichtig:

etc_dnsmasq_d = true

DNS-Records liegen in:

/opt/heimgewebe/dns/pihole/etc-dnsmasq.d/

Canonical Records:

leitstand.heimgewebe.home.arpa → 192.168.178.46
api.heimgewebe.home.arpa       → 192.168.178.46
heimgewebe.home.arpa           → 192.168.178.46


⸻

DNS-Philosophie

These: Client-DNS individuell konfigurieren.
Antithese: Router-DNS global erzwingen.
Synthese: Router verweist auf Pi-hole → Clients automatisch.

Empfehlung:
Fritzbox DNS → 192.168.178.46
Clients → „Automatisch“

⸻

3. Reverse Proxy

Caddy

Bind-Mount:

/opt/heimgewebe/edge/Caddyfile → /etc/caddy/Caddyfile

Canonical Host:

leitstand.heimgewebe.home.arpa

HTTP → 308 Redirect
HTTPS → reverse_proxy → deploy-leitstand-1:3000
TLS → internal CA

⸻

TLS

Root-CA:

/opt/heimgewebe/edge/certs/caddy-local-root.crt

Muss auf Clients vertraut werden.

⸻

4. WireGuard

Interface

10.7.0.1/24

Peer (iPad):

10.7.0.2/32

Server wg0.conf:

AllowedIPs = 10.7.0.2/32

Client AllowedIPs:

192.168.178.0/24, 10.7.0.0/24

DNS im WG-Profil:

192.168.178.46


⸻

NAT

iptables -t nat -A POSTROUTING -s 10.7.0.0/24 -o eno2 -j MASQUERADE

IP-Forward:

net.ipv4.ip_forward = 1


⸻

5. Service-Layer

Leitstand

Container: deploy-leitstand-1
Port intern: 3000

Nur via Caddy erreichbar.

⸻

Weltgewebe API

Container: weltgewebe-api
Port intern: 8080

Exposed via Caddy.

⸻

6. Zugriffsmatrix

Herkunft	DNS	Routing	TLS	Ergebnis
LAN	Pi-hole	direkt	trusted CA	OK
WireGuard	Pi-hole	NAT → LAN	trusted CA	OK
Internet	—	nicht geroutet	—	blockiert


⸻

7. Drift-Gefahren
	•	Router-DNS ≠ Pi-hole
	•	WG-Client-DNS falsch
	•	Falsche AllowedIPs
	•	Caddyfile nicht neu geladen
	•	etc_dnsmasq_d deaktiviert

⸻

8. Systemessenz

Heimserver ist kohärent, wenn:
	•	DNS autoritativ ist
	•	Caddy Host-Match korrekt ist
	•	WG Routing deterministisch ist
	•	Kein Split-Brain existiert

⸻

Unsicherheitsgrad

0.08

Ursachen:
	•	IPv6 nur teilvalidiert
	•	Router-Konfig nicht versioniert
	•	Kein zentrales Health-Monitoring

Interpolationsgrad:

0.05

Annahmen:
	•	Fritzbox DNS stabil
	•	Kein zweiter Resolver aktiv
	•	Keine parallele VLAN-Topologie

⸻

Verdichtete Essenz

Heimserver = DNS + Routing + Proxy + Tunnel.

Fällt einer dieser vier Pfeiler,
zerfällt der Zugriff.

⸻

⸻

Architektur-Topologie (ASCII)

                     INTERNET
                         │
                         │ (UDP 51820)
                         ▼
                    [ Fritzbox ]
                         │
                         │
        ┌────────────────┴────────────────┐
        │                                   │
        ▼                                   ▼
   LAN 192.168.178.0/24              WireGuard 10.7.0.0/24
        │                                   │
        │                                   │
        ▼                                   ▼
               ┌─────────────────────────┐
               │      Heimserver         │
               │ 192.168.178.46          │
               │                         │
               │  ┌───────────────────┐  │
               │  │ Pi-hole (DNS)     │  │
               │  │ Port 53           │  │
               │  └───────────────────┘  │
               │                         │
               │  ┌───────────────────┐  │
               │  │ Caddy             │  │
               │  │ :80 / :443        │  │
               │  └───────────────────┘  │
               │            │            │
               │            ▼            │
               │     deploy-leitstand    │
               │          :3000          │
               │                         │
               └─────────────────────────┘


⸻

Betriebszustand (grün)
	•	dig → 192.168.178.46
	•	curl HTTP → 308
	•	curl HTTPS → 200
	•	wg show → handshake aktiv
	•	iPad WireGuard aktiv → Seite lädt

⸻

Trockene Wahrheit:

Netzwerke sterben nie durch Gewalt.
Sie sterben durch Nebenannahmen.
