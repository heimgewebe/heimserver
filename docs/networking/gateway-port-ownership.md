# Gateway Port Ownership & Host-Network Constraints

**Dokumentklasse:** ARCHITEKTUR · INVARIANTE
**Stand:** 2026-02-13
**Scope:** Host-Namespace Ports 80, 443, 53, 8081

---

## 1. Zielbild: Expositions-Singularität

Es existiert genau ein öffentlich exponierendes Gateway im System.

*   **Single Point of Entry:** Caddy (Edge) terminiert TLS für alle Subdomains.
*   **Kein Bypass:** Kein anderer Container darf direkt auf 80/443 lauschen.

## 2. Port-Matrix (Host-Namespace)

| Port | Service | Typ | Modus | Anmerkung |
| :--- | :--- | :--- | :--- | :--- |
| **80** | `edge-caddy` (Caddy) | TCP | Host (Docker-Proxy) | HTTP Redirect |
| **443** | `edge-caddy` (Caddy) | TCP | Host (Docker-Proxy) | TLS Termination (UDP/443 nur bei aktivem QUIC/HTTP3) |
| **53** | `dns-pihole` | TCP/UDP | **Host-Network** | DNS Resolver |
| **8081** | `dns-pihole` | TCP | **Host-Network** | Webinterface (verschoben) |

**Wichtig:**
Services im `network_mode: host` (wie Pi-hole) teilen sich den Netzwerk-Namespace mit dem Host. Jede Port-Bindung kollidiert direkt mit anderen Host-Diensten.

## 3. Host-Mode Risiken

Der Container `dns-pihole` läuft im `host`-Mode, um korrekte Client-IPs für DNS-Queries zu sehen.
Das bedeutet aber:
*   Der Container "sieht" alle Host-Interfaces.
*   Standardmäßig bindet Pi-hole Webinterface auf 80.
*   **Konflikt:** Startet Pi-hole vor Caddy, belegt es Port 80. Caddy crashed ("Address already in use").

**Invariante:**
Jeder Service im Host-Mode muss explizit auf kollisionsfreie Ports konfiguriert werden.

## 4. Diagnose

Prüfen, wer die Ports belegt:

```bash
# Zeigt Listener mit Prozessnamen (inkl. UDP)
sudo ss -lntup | grep -E ":(80|443|53|8081)"
```

Erwarteter Output (Beispiel):
```text
LISTEN 0      4096         0.0.0.0:80        0.0.0.0:*    users:(("docker-proxy",pid=...))
LISTEN 0      4096         0.0.0.0:443       0.0.0.0:*    users:(("docker-proxy",pid=...))
LISTEN 0      32     192.168.178.46:53       0.0.0.0:*    users:(("pihole-FTL",pid=...))
LISTEN 0      5           0.0.0.0:8081      0.0.0.0:*    users:(("pihole-FTL",pid=...) ("lighttpd",pid=...))
```

*   `docker-proxy` auf 80/443 -> OK (Caddy via Bridge)
*   `lighttpd` / `pihole-FTL` auf 53/8081 -> OK (Pi-hole Host-Mode)

Falls `lighttpd` auf 80 auftaucht -> **ALARM / DRIFT**.

## 5. Wiederherstellung (Recovery)

Falls Pi-hole Port 80 blockiert:

1.  **Identifizieren & Stop:**
    ```bash
    docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -i pihole
    docker stop dns-pihole
    ```
2.  **Prüfen:**
    ```bash
    sudo ss -lntup | grep :80
    ```
    (Sollte leer sein oder `docker-proxy` (Caddy) zeigen)
3.  **Config korrigieren (Environment):**
    In `docker-compose.yml` (oder Override):
    ```yaml
    environment:
      - WEB_PORT=8081
    ```
    Und in `etc-pihole/setupVars.conf` prüfen.
4.  **Neustart:**
    ```bash
    docker start dns-pihole
    ```

## 6. Routing-Implikationen

*   Requests an `http://pihole.heimgewebe.home.arpa` landen auf Port 80 (Caddy).
*   Caddy proxied intern an `http://<HOST_IP>:8081`.
*   Benutzer merkt nichts von Port 8081 (transparenter Proxy).

```mermaid
graph LR
    User -->|HTTPS/443| Caddy
    Caddy -->|HTTP/8081| PiHole[Pi-hole (Host-Mode)]
```
