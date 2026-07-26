---
id: heimnetz-2026
role: norm
status: deprecated
canonicality: explanatory
doc_type: architecture
title: Historische Blaupause: Heimnetz 2026+
summary: Supersedierte Zielarchitektur für den früheren kombinierten Einsatz von Heimserver und Heimberry
last_reviewed: 2026-07-26
depends_on:
  - constitution
  - network
  - naming
  - port-matrix
related_docs: []
verifies_with:
  - scripts/tests/test_preflight_mock.sh
  - scripts/tests/test_caddy_template.py
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historische Blaupause: Heimnetz 2026+

> **Historische Referenz.** Dieses Dokument beschreibt die frühere Heimserver-Architektur. Heimserver ist außer Betrieb und besitzt keine aktive Rolle, Exposition, Autorität oder Recovery-Abhängigkeit. Der aktuelle Zielzustand liegt in [`heimgewebe/infra@e1245b5…:INFRA_CONSTITUTION.md`](https://github.com/heimgewebe/infra/blob/e1245b502393edcdb42d0f20317c8a5a2c2defbe/INFRA_CONSTITUTION.md). Die folgenden Inhalte dürfen nicht als heutige Betriebsfreigabe gelesen oder ausgeführt werden.


> **Status-Hinweis:**
> Dieses Dokument beschreibt einen supersedierten früheren Blueprint.
> Es definiert keinen angestrebten oder ausführbaren Endzustand mehr.

---
## 0. Leitprinzipien (kanonisch, präzisiert)
1. **Single Source of Truth (SoT):**
   DNS/Name → **Heimberry** (erzwingbar, nicht nur intendiert)
2. **Strikte Ebenentrennung:**
   **Truth ≠ Service ≠ Interaction ≠ Access**
3. **Internal-First + kontrollierte Public-Exception:**
   Kein direkter öffentlicher Ingress für interne Dienste. Zugriff erfolgt
   standardmäßig über ein authentifiziertes Overlay. Einzige öffentliche
   Ausnahme sind `weltgewebe.net`, `www.weltgewebe.net` und
   `api.weltgewebe.net` über Edge-Caddy TCP 80/443 auf dem Heimserver.
   (Hinweis: Das Overlay nutzt das Internet als Transportschicht und ist nicht
   mit physischer Isolation zu verwechseln.)
4. **Determinismus vor Komfort:**
   Jeder Request ist rekonstruierbar (DNS → Proxy → Service)
5. **Eindeutige Abbildung:**
   `1 FQDN → 1 IP → 1 Proxy → 1 Upstream`
6. **Kontrollierte Fehlertoleranz:**
   Fehler führen zu **vorhersehbaren, degradierten Zuständen**, anstatt das Gesamtsystem untrennbar ausfallen zu lassen.
7. **Enforcement vor Konvention:**
   Regeln gelten nur, wenn sie technisch erzwungen und kontinuierlich verifiziert werden.
8. **Epistemische Ehrlichkeit (Determinismus vs. Realität):**
   Determinismus ist ein Architekturziel, keine absolute Garantie. Client-Verhalten (z.B. DoH/DoT, harte OS-Resolver) kann diesen partiell unterlaufen. Das System ist darauf ausgelegt, dies zu begrenzen und sichtbar zu machen, nicht vollständig zu eliminieren.
9. **Betriebsphilosophie:**
   Dieses System optimiert primär auf Erklärbarkeit und Kontrolle, nicht auf maximal unsichtbare Resilienz. Es bevorzugt sichtbare Fehler vor stiller Mehrdeutigkeit.
---
## 0.5 OS-Versionierungsstrategie
### Ziel
Trennung von:
- **Architektur-Invariante** (was das System ist)
- **Implementierungsbasis** (welche Debian-Version läuft)
### Regeln
1. OS = Raspberry Pi OS Lite (64-bit) ist invariant
2. Debian-Version ist variabel (Bookworm, Trixie, …)
3. Upgrade erfolgt nur nach erfolgreichem Realitätscheck
### Validierung vor Upgrade
- `dig` gegen Heimberry stabil
- Pi-hole Query-Log ohne Anomalien
- Tailscale DNS Override funktioniert
- keine DoH-Leaks durch Regression
### Rollback-Fähigkeit
- Image-basierter Restore muss möglich sein
- SD-Karten-Backup vor Upgrade verpflichtend
### Prinzip
„Stabilität wird gemessen, nicht angenommen.“
---
## 1. Geräte-Rollen (final, gehärtet)

### 1.1 Heimberry — **Truth Layer**
**OS/Runtime:** Raspberry Pi OS Lite (64-bit) + Docker
**Policy:**
Die konkrete Debian-Basis (z.B. Bookworm, Trixie) ist **nicht kanonisch festgelegt**,
sondern folgt dem Prinzip:
→ „neueste stabile Version, sofern Validierung bestanden“
Eine Version wird nur dann übernommen, wenn:
- Pi-hole + Unbound stabil laufen
- Tailscale DNS korrekt integriert ist
- keine Resolver-Regressionen auftreten
**Pflichtdienste:**
* Pi-hole (DNS authoritative + filtering)
* Unbound (rekursiver Resolver)
* Tailscale (Subnet Router + DNS Advertiser)
**Optionale Dienste:**
* DHCP (nur bei vollständiger Router-Deaktivierung)
* node-exporter (Observability)
* Weltgewebe-DynDNS-Updater (outbound-only; keine eingehenden Ports)
**Explizit ausgeschlossen:**
* kein Reverse Proxy
* keine App-Container
* keine GUI / Dev / Media
* kein eingehender Internetdienst für Weltgewebe oder andere Apps
**Invarianten:**
* einziger primärer Resolver für `home.arpa`
* primäre Quelle für DNS-Antworten
* alle Clients nutzen primär Heimberry
**Betriebsanforderungen (Bewusster SPOF):**
Die Rolle als einziger DNS-Knoten macht den Heimberry zu einem strukturellen SPOF. Dies wird bewusst akzeptiert zugunsten architektonischer Klarheit. Es wird keine Pseudo-HA oder zweite DNS-Wahrheit eingeführt. Ein Ausfall bedeutet den Verlust der FQDN-Auflösung, was degradierte Zustände erzwingt (siehe Failure-Tiering). Die Resilienz beschränkt sich auf:
* **Monitoring:** Erreichbarkeit und DNS-Antwortzeiten müssen extern (z.B. vom Heimserver) überwacht werden.
* **Recovery:** Automatischer Docker-Restart bei Crash; dokumentierte manuelle Restart-Prozedur für das OS. Striktes "Restore-from-zero" Zeitbudget: < 15 Minuten.
* **Backup:** Tägliche Backups der Pi-hole-Konfiguration und Tailscale-State auf ein externes Ziel.
---

### 1.2 Heimserver — **Service Layer**
**Runtime:** Docker + Compose
**Pflichtdienste:**
* Caddy (Reverse Proxy + interne CA)
* Applikationen
**Optionale Dienste:**
* Worker / Queues
* interne Tools (nicht kanonisch)
**Explizit ausgeschlossen:**
* kein primäres DNS
* kein VPN-Core
* keine Dev-Primärumgebung
**Invarianten:**
* alle Services nur über Caddy erreichbar
* keine direkten Containerports
* stellt Monitoring-Watchdog für Heimberry bereit
---

### 1.3 Heim-PC — **Interaction Layer**
**Rolle:** Entwicklung + GPU + Zustandsträger
**Pflichtdienste:**
* VS Code / Toolchain
* Sunshine
**Optionale Dienste:**
* temporäre Testcontainer (nicht persistent)
**Explizit ausgeschlossen:**
* keine Netzwerkautorität
* kein Proxy / primäres DNS
**Invarianten:**
* einziger kanonischer Dev-State
* keine parallelen Arbeitskopien als Wahrheit
---

### 1.4 iPad — **Access Layer**
**Rolle:** Zustandsloser Zugriff
**Tools:**
* Moonlight
* Tailscale
* optional SSH
**Invariante:**
* keine Persistenz
* keine lokale Logik
---
## 2. Netzwerk-Topologie (präzisiert)

### 2.1 LAN
* `192.168.178.0/24`
* Heimberry: `192.168.178.2`
* Heimserver: `192.168.178.46`
* Heim-PC: `192.168.178.25`

### 2.2 Overlay
* ausschließlich **Tailscale**
Heimberry (Primärer Router/DNS):
```bash
tailscale up \
  --advertise-routes=192.168.178.0/24 \
  --accept-dns=false
```

### 2.3 Routing-Invarianten
* kein Portforwarding
  * Ausnahme: TCP 80/443 zur Edge-Caddy-Frontdoor des Heimservers ausschließlich für `weltgewebe.net`, `www.weltgewebe.net`, `api.weltgewebe.net`.
* kein Dual-VPN
* kein implizites Routing
* kein Internet-Ingress außer der dokumentierten Weltgewebe-Public-Exception
---
## 3. DNS-Architektur & Resilienz (erzwingbar gemacht)

### 3.1 Root
* `home.arpa`

### 3.2 Zonen
* `heimgewebe.home.arpa`
* `weltgewebe.home.arpa`

### 3.3 Harte Regeln & Resilienz-Strategie
* Primär: Heimberry = primärer Nameserver für alle Zonen. `home.arpa` bleibt exklusiv Heimberry-geführt.
* Secondary/Fallback (Neu): Tailscale MagicDNS ist NICHT sekundäre Wahrheit für `home.arpa`. Es ist ein separater administrativer Notzugangspfad außerhalb des kanonischen Heimnetz-Namensraums für kritische Knoten-IPs, falls Heimberry ausfällt. Ein degradierter Betrieb bedeutet hier nicht, dass sich die DNS-Wahrheit verlagert, sondern nur, dass ein eingeschränkter Admin-Zugriff möglich bleibt.
* Router DHCP Ziel: Kein konkurrierender zweiter Resolver im DHCP. Keine gleichrangigen DNS-Server verteilen. Notfallpfade laufen bewusst außerhalb von DHCP.
* Tailscale DNS → Heimberry.

### 3.4 Enforcement (Konkretisiert)
Clients müssen explizit konfiguriert werden.
Klassifikation der Mechanismen:
* HART ERZWINGBAR: Linux/Server (`resolv.conf` hardcoded auf nameserver `192.168.178.2`), Tailscale DNS-Settings (Override Local DNS erzwingt Heimberry für Tailnet-Clients).
* WEITGEHEND ERZWINGBAR: Router DHCP (DHCP-Option 6 verteilt ausschließlich `192.168.178.2`, wird aber nur von kooperativen Clients übernommen).
* NUR DETEKTIERBAR / BEGRENZBAR: Client-DoH/DoT-Verhalten.

Überprüfbare Bedingung (CI/Monitoring):
```bash
# Muss immer eine IP liefern, nicht NXDOMAIN oder Timeout
dig @192.168.178.2 leitstand.heimgewebe.home.arpa +short
```

Client-Realität und operative Grenzen:
Determinismus ist im Netzwerk nur partiell erzwingbar. Realistisch problematische Klassen sind iOS/iPadOS (die oft eigene DNS-Wege bevorzugen), Browser mit integriertem DoH, sowie Smart Devices/IoT mit hartcodierten Resolvern. Maßnahmen: Bekannte DoH/DoT-Bootstrap-Server werden blockiert. Unkooperative Clients, die lokales DNS vollständig verweigern, werden isoliert (z.B. Gast-VLAN). Abweichungen sollen sichtbar gemacht, aber nicht um jeden Preis technisch (z.B. via SSL-Interception) verhindert werden.
---
## 4. DNS-Stack
```
Client → Pi-hole → Unbound → Root
```
**Invarianten**
* kein externer Upstream im Pi-hole (immer Unbound)
* keine zweite aktive vollwertige Resolverinstanz (MagicDNS ist nur Notnagel)
* keine lokalen Overrides in `/etc/hosts` für Produktionsdienste
---
## 5. Reverse Proxy & TLS (gehärtet)
**Ort**
* ausschließlich Heimserver
**Regeln**
* jede App → FQDN
* interne CA verpflichtend
* kein Direktzugriff auf Container
**Beispiel**
```
leitstand.heimgewebe.home.arpa {
    reverse_proxy http://leitstand:3000
}
```
**Enforcement (Konkretisiert)**
* Docker Compose (Heimserver): App-Container binden Ports ausschließlich an `127.0.0.1` oder spezifisch an ein isoliertes Caddy-Netzwerk. Striktes Verbot von `ports: - "3000:3000"` ohne IP-Bindung für alle Dienste, außer Caddy selbst. Caddy verwaltet als einziger Dienst die Host-Ports 80/443.

*Hinweis:*
Dieses Modell (127.0.0.1-Bindung) ersetzt perspektivisch das aktuelle Firewall-basierte Exposure-Modell, ist aber noch nicht kanonisch durchgesetzt.

* Host Firewall (UFW/iptables):
    * Heimberry: Erlaubt Port 53 (DNS) aus dem LAN und Tailnet sowie Tailscale-interne Ports. Pi-hole Webinterface ist strikt auf Tailnet-only (`tailscale0` interface) beschränkt.
    * Heimserver: Erlaubt Ports 80/443 für Edge-Caddy. Öffentlich ist darauf ausschließlich die Weltgewebe-Public-Exception für `weltgewebe.net`, `www.weltgewebe.net` und `api.weltgewebe.net` zulässig. Port 22 (SSH) als Admin-Zugang ist aus dem LAN und Tailnet erlaubt. Alle direkten App-, Admin- und DB-Ports von außen sind strikt verboten.
    * Heim-PC: Erlaubt Sunshine-Ports und Port 22 (SSH) ausschließlich Tailnet-only (`tailscale0` interface).
---
## 6. Access Layer (VPN, final)
**Entscheidung**
**Zielzustand:**
* ausschließlich Tailscale
**Übergang:**
* bestehende WireGuard-Infrastruktur bleibt bis zur Migration bestehen
**Funktionen**
* Device Mesh
* Subnet Routing
* DNS Integration
**DNS-Konfig**
* Nameserver → Heimberry
* MagicDNS aktiv, aber streng limitiert als separater administrativer Notzugang (nicht als kanonischer Fallback)
**Invarianten**
* kein zweites VPN
* keine alternative Routinglogik
---
## 7. Remote Development (präzisiert)
**Primär**
```
iPad → Tailscale → Heim-PC → Moonlight → Dev
```
**Sekundär**
```
iPad → Heimserver → SSH/code-server
```
**Regeln**
* Dev-State nur auf Heim-PC
* keine Cloud als Primärsystem
* keine Sync-basierten Doppelzustände
---
## 8. Port-Disziplin
**Heimberry**
* 53 (DNS) - LAN & Tailnet
* Tailscale intern
* Pi-hole Webinterface - Tailnet-only
**Heimserver**
* 80/443 (Caddy) - LAN & Tailnet; public nur für `weltgewebe.net`, `www.weltgewebe.net`, `api.weltgewebe.net`
* 22 (SSH) - LAN & Tailnet
**Heim-PC**
* Sunshine Ports - Tailnet-only
* 22 (SSH) - Tailnet-only
**Global**
* keine offenen Internetports außer Edge-Caddy TCP 80/443 für die dokumentierte Weltgewebe-Public-Exception
* keine direkten Serviceports
---
## 9. IPv6-Policy (explizit gehärtet)
**Zustand**
* IPv6 ist derzeit bewusst ausgeklammert (deaktiviert), um die Komplexität im Zielzustand zu reduzieren. Dies ist eine operative Vereinfachung, keine metaphysische Wahrheit oder dauerhafte architektonische Ablehnung.
**Enforcement**
* Router IPv6 aus
* OS-Level (`sysctl net.ipv6.conf.all.disable_ipv6=1`) deaktiviert
**Aktivierung nur wenn:**
* DNS vollständig IPv6-fähig
* Pi-hole + Unbound integriert
* kein paralleler Resolver entsteht
---
## 10. Sicherheitsmodell
* Zero Trust via Overlay
* interne TLS-CA verpflichtend
* keine extern erreichbaren Dienste außer `weltgewebe.net`, `www.weltgewebe.net` und `api.weltgewebe.net` über Edge-Caddy TCP 80/443
* keine impliziten Trust-Zonen
---
## 11. Observability (erweitert)
**Minimal**
* Pi-hole Query Logs
* Caddy Access Logs
**Erweiterung**
* Heimberry Health-Check: Skript auf dem Heimserver prüft minütlich DNS-Auflösung und alarmiert bei Ausfall.
* zentraler Log-Aggregator (optional)
* Query-Tracing möglich
**Ziel**
jede Anfrage nachvollziehbar:
Client → DNS → Proxy → Service
---
## 12. Drift-Prevention (erzwingbar)
**Verbote und menschliche Risiken**
* `/etc/hosts` Overrides bleiben im Normalbetrieb strikt verboten. Temporäre Incident-Overrides sind nur auf definierten Admin-Clients zulässig, sind dokumentations- und rollbackpflichtig, und gelten ausdrücklich nicht als kanonische Konfiguration.
* lokale DNS-Resolver
* direkte Ports
* Shadow-Proxies
Der menschliche Faktor: Eine hohe Regelstrenge provoziert in der Praxis Shadow-Configs, wenn offizielle Wege zu aufwendig sind. Verbote allein verhindern Drift nicht. Sichtbarkeit (Logs, Monitoring) und einfache Recovery-Pfade sind ebenso wichtig wie das Regelwerk selbst.
**Regel für neue Services**
DNS → Caddy → Container
---
## 13. Failure-Tiering (Fehlertoleranz-Modell)
Das System muss vorhersehbar reagieren, wenn Komponenten ausfallen.
**Zustand 1: Normalbetrieb**
Alle Systeme online.
* Routing: FQDNs werden via Heimberry aufgelöst.
* Services: Voller Zugriff via Caddy mit TLS.
**Zustand 2: Degradierter Admin-Zugriff (Heimberry offline)**
Heimberry (DNS) fällt aus, aber Heimserver & PC laufen noch.
* Was funktioniert noch: Physische Verbindungen, IP-Routing, Tailscale-Verbindungen. Services laufen im Hintergrund weiter.
* Was ist kaputt: Kanonische `.home.arpa` DNS-Auflösung schlägt global fehl. Ad-Filtering ist inaktiv.
* Gültige Namenspfade: Nur MagicDNS Node-Namen (`heimserver`, `heim-pc`) als administrativer Notzugang. Kanonische FQDNs sind offline.
* Zulässige Zugriffswege (Degraded Access Path):
    * SSH-Zugriff über IP (192.168.178.46 oder Tailscale-IP).
    * Administrative Zugriffe über MagicDNS Node-Namen.
* Temporäre Ausnahmen: Lokale `/etc/hosts` Notfall-Einträge auf definierten Admin-Clients für kritische Caddy-Dienste (dokumentations- und rollbackpflichtig).
* Aktion: Prio 1 Restart Heimberry.
**Zustand 2b: Degradierter App-Betrieb**
DNS ist online, aber Reverse Proxy (Caddy) ist in Teilen gestört oder intern blockiert.
* Was funktioniert noch: DNS-Auflösung.
* Was ist kaputt: App-Erreichbarkeit über FQDNs.
* Zulässige Zugriffswege: Lokales Port-Forwarding (SSH-Tunnel) an `127.0.0.1` des Heimservers zur Diagnose. Direkte IP-Zugriffe bleiben verboten.
**Zustand 3: Total Failure (Heimserver offline)**
Heimserver (Proxy/Services) fällt aus.
* Was funktioniert noch: DNS funktioniert weiterhin (wenn Heimberry online), liefert aber “Connection Refused” auf FQDNs.
* Was ist kaputt: Alle Applikationen nicht erreichbar. Reverse Proxy offline.
* Zulässige Zugriffswege: Direkter physischer oder SSH-Zugriff auf Heimserver (via IP oder MagicDNS) zur Fehlerbehebung.
* Aktion: Wiederherstellung des Service-Layers.
**Designziel**
Fehler sind lokalisierbar, eindeutig und erlauben administrativen Notfallzugriff.
---
## 14. Gehärteter Migrationsplan
**Vor Phase 1:**
- Auswahl OS-Version nach Validierungsmatrix (im Rahmen dieses Plans gepflegte Prüfliste: Hardware-/Architektur-Support, Kernel-/Treiber-Stabilität, Kompatibilität mit Container-/Netzwerk-Stack, Verfügbarkeit von Sicherheitsupdates sowie erfolgreich getestetes Backup/Restore).
- Empfehlung: aktuelle stabile Raspberry Pi OS Lite Version
**Optionaler Safepath:**
- Erstinstallation auf älterer stabiler Basis (z.B. Bookworm)
- danach kontrolliertes Upgrade testen

**Phase 1 — Truth (Risiko-Minimiert)**
* Heimberry deployen & konfigurieren
* Parallelbetrieb: Router DNS bleibt vorerst unverändert. Einzelne Clients (z.B. Admin-PC) manuell auf Heimberry umstellen.
* Validierung: `dig @192.168.178.2 google.com` und `dig @192.168.178.2 leitstand.heimgewebe.home.arpa` müssen stabil antworten.
* Router DNS auf Heimberry umstellen (mit 24h Überwachungsphase).
* Rollback-Plan: Bei Störungen im LAN Router-DHCP sofort zurück auf Provider-DNS stellen.
**Phase 2 — Access**
* Tailscale auf allen Geräten
* Subnet Routing aktivieren
* Tailscale DNS auf Heimberry lenken
Validierung: iPad erreicht interne FQDNs ohne lokales WLAN.
* Rollback-Plan: Deaktivierung von “Override Local DNS” in der Tailscale Admin Console.
**Phase 3 — Service**
* Caddy konsolidieren
* Container-Ports von `0.0.0.0` auf `127.0.0.1` oder internes Docker-Netz umstellen.
Validierung: `curl http://heimserver:3000` (direkter Port) muss fehlschlagen, `curl https://leitstand.heimgewebe.home.arpa` muss funktionieren.
* Rollback-Plan: Revert der `docker-compose.yml` Port-Bindings auf `0.0.0.0`, falls Caddy-Routing unvorhergesehene Fehler wirft.
**Phase 4 — Interaction**
* Sunshine stabilisieren
**Phase 5 — Cleanup**
* WireGuard entfernen
* alte DNS (alte Pi-holes etc.) löschen
---
## 15. Invarianten (unverhandelbar)
1. DNS = Heimberry (primär)
2. Overlay = Tailscale
3. Proxy = Heimserver
4. Dev = Heim-PC
5. kein Splitbrain (keine zwei gleichwertigen Wahrheiten)
6. keine Direkt-Exposures
---
## 16. Anti-Patterns
* Dual DNS (zwei unterschiedliche DNS Server im DHCP, führt zu zufälligen Ergebnissen)
* Dual VPN
* mehrere Proxies
* exposed Container
* mehrere Dev-Wahrheiten
* halb aktiviertes IPv6
---
## 17. Essenz
**Struktur:**
* Heimberry → Wahrheit
* Heimserver → Dienste
* Heim-PC → Interaktion
* iPad → Zugriff
**Logik:**
→ Wahrheit zentral
→ Zugriff flexibel
→ Ausführung isoliert
→ Regeln erzwingbar und bei Ausfall vorhersehbar
---
## 18. Bewusste Tradeoffs
Dieses System ist eine Entscheidung für Erklärbarkeit.
**Was gewonnen wird:**
* Klarheit und explizite Wahrheiten
* Einfache Debugbarkeit (linearer Request-Pfad)
* Kohärenz (Single Source of Truth)
**Was bewusst geopfert wird:**
* Komfort (kein „it just works“ bei Ausfällen)
* Implizite Resilienz (keine automatischen Fallbacks auf Provider-DNS)
* Toleranz gegenüber wilden Clients
---
## 19. Unsicherheits- & Interpolationsanalyse
**Unsicherheitsgrad:** 0.15 (gesenkt durch Failure-Tiering)
**Ursachen:**
* Reale Last des Heimberrys unter Volllast ist aktuell nur eine Annahme.
* Das genaue Client-Verhalten bei MagicDNS-Fallback in echten Störungsszenarien muss erst in der Validierungsphase getestet werden.
* Neue Unsicherheitsquelle:
  - Unterschiedliches Verhalten zwischen Debian-Versionen
    (insbesondere DNS-Resolver, systemd-resolved, nftables)
* Mitigation:
  - OS-Version wird als testpflichtige Variable behandelt
**Interpolationsgrad:** 0.20
**Annahmen:**
* Die vollständige DNS-Disziplin ist operativ durchhaltbar, ohne dass der administrative Schmerz zu Shadow-IT führt.
* MagicDNS reicht als administrativer Notfall-Zugriff.
* Die Heimberry-Hardware ist hinreichend stabil.
Testbar sind die harten Enforcement-Regeln (Firewall, DNS-Verteilung); nicht vorab testbar ist das menschliche Verhalten im langfristigen Betrieb.
---
## 20. Abgrenzung: Kanonische Wahrheit vs. Administrativer Notpfad
Um Splitbrain-Szenarien und Architekturdrift zu vermeiden, wird hiermit explizit getrennt:
* **Kanonischer DNS-Raum (`home.arpa`):** Die exklusive, autoritative Quelle für alle Dienste und Endpunkte im Normalbetrieb. Wird ausschließlich von Heimberry bereitgestellt.
* **Notzugang über Tailscale/MagicDNS:** Ein separater, isolierter Namensraum (Node-Namen), der nicht Teil der kanonischen Architektur ist. Er dient ausschließlich dem administrativen Notfallzugriff, wenn der kanonische Raum gestört ist.
* **Nicht-kanonische Incident-Hilfen:** Temporäre Overrides (z.B. `/etc/hosts` auf Admin-Maschinen) sind explizit keine Architekturmerkmale, sondern operative Werkzeuge für den Ausfallmodus. Sie unterliegen einer strikten Rollback-Pflicht nach Behebung des Incidents.
---
## 21. Runtime-Detection (Drift & DNS-Bypass)
Das System hat Regeln; es benötigt zwingend Sichtbarkeit, um deren Einhaltung empirisch zu prüfen.
**Erkennung von DNS-Bypass:**
* Firewall-Logs (Router): Zählung von TCP/UDP Port 53, 853 (DoT) Traffic, der den Router ansteuert oder an externe IPs (z.B. `8.8.8.8`, `1.1.1.1`) gerichtet ist.
* DNS-Metrik: Messung des Volumens an DNS-Queries am Heimberry pro Client. Unerklärliche Einbrüche weisen auf DoH-Aktivierung im Browser/OS hin.
**Erkennung von Shadow-Configs:**
* SSH-Logins und Caddy Access-Logs auswerten. Traffic auf inoffiziellen Ports identifizieren.
* Nmap/Portscans aus dem Tailnet: Sind nur die erwarteten Ports offen?
  * Heimberry: erwartbar 53 plus definierte Admin-/Tailnet-Pfade
  * Heimserver: erwartbar 80/443, 22; extern nur Edge-Caddy TCP 80/443 für die drei Weltgewebe-Public-Hosts
  * Heim-PC: erwartbar Sunshine + 22 Tailnet-only
**Ziel-Metrik:** > 95% aller legitimen DNS-Requests im LAN/Tailnet werden vom Heimberry beantwortet.
---
## 22. Operational Proof (Realitätscheck)
Architektur-Annahmen müssen durch harte Realitätstests validiert werden, um vom Soll- in den Ist-Zustand zu wechseln.
**Messbare Tests (quartalsweise):**
* DNS-Ausfall simulieren: Heimberry-Docker-Container stoppen. Messen, ab wann Caddy/Clients Alarm schlagen.
* Recovery proben: Heimberry hart rebooten.
* Client-Bypass provozieren: Auf einem Test-Client manuell DoH aktivieren oder `8.8.8.8` eintragen. Prüfen, ob die Router-Firewall/Pi-hole greift oder der Client “entkommt”.
**Harte Zielwerte:**
* Real Measured Recovery (Heimberry OS-Reboot bis DNS antwortet): < 5 Minuten.
* Erfolgsquote DNS-Disziplin: Abfang-Rate unkooperativer Clients bei manuellem Bypass-Versuch > 90%.
---
## 23. Minimales Notfall-Runbook
Keine Theorie, sondern operative Handlung bei Totalausfall.
**Szenario 1: Heimberry (DNS) tot**
1. **Zugriff:** `ssh user@192.168.178.2` (oder via MagicDNS `ssh user@heimberry`).
2. **Docker prüfen:** `docker ps | grep pihole`.
3. **Neustart:** `docker-compose restart` oder `systemctl restart docker`.
4. **Hard-Reset:** `sudo reboot`.
5. **Wenn Hardware defekt:** Router DHCP-DNS manuell auf Provider-Standard (z.B. `1.1.1.1` oder Router-IP) ändern, um Internet für das LAN wiederherzustellen (führt zu Totalverlust lokaler FQDNs).
**Szenario 2: Caddy (Reverse Proxy) kaputt**
1. **Zugriff:** `ssh user@192.168.178.46` (oder via MagicDNS `ssh user@heimserver`).
2. **Logs prüfen:** `docker logs caddy --tail 50`.
3. **Config Test:** `docker exec -w /etc/caddy caddy caddy validate`.
4. **Neustart:** `docker restart caddy`.
5. **Not-Zugriff:** Via SSH lokales Port-Forwarding aufbauen (`ssh -L 3000:localhost:3000 user@heimserver`), um intern an die blockierten App-Ports (`127.0.0.1`) zu gelangen.
