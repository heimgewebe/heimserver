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
LISTEN 0      5           0.0.0.0:8081      0.0.0.0:*    users:(("pihole-FTL",pid=...))
```

*   `docker-proxy` auf 80/443 -> OK (Ports werden vom Edge-Container publisht)
*   `pihole-FTL` auf 53/8081 -> OK (Pi-hole Host-Mode)

*Hinweis:* Je nach Pi-hole-Version kann der Prozessname abweichen (z.B. `lighttpd` bei Legacy-Setups).

Falls `lighttpd` oder `pihole-FTL` auf 80 auftaucht -> **ALARM / DRIFT**.

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
3.  **Config korrigieren (FTL v6):**
    ```bash
    # Setze Webserver Port via FTL Config (Beispiel)
    docker start dns-pihole
    docker exec -it dns-pihole sh -lc 'pihole-FTL --config webserver.port "8081o,[::]:8081o"'
    docker restart dns-pihole
    ```
    *Hinweis:* Falls Pi-hole nicht via FTL konfiguriert wird (Legacy/lighttpd), müssen Environment-Variablen (z.B. `WEB_PORT`) je nach Deployment angepasst werden.
4.  **Kontrolle:**
    ```bash
    curl -I http://localhost:8081/admin/
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
