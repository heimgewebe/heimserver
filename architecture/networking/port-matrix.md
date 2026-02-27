# Port-Matrix Heimserver & Gateway-Ownership

**Dokumentklasse:** ARCHITEKTUR · INVARIANTE
**Stand:** 2026-02-25
**Scope:** Host-Namespace Ports (TCP/UDP)

---

## 1. Zielbild: Kollisionsarme Trennung

Um Konflikte zwischen Host-Diensten (Pi-hole), Infrastruktur (SSH/WireGuard) und Applikationen (Weltgewebe) zu verhindern, gilt das Prinzip: **Ein Owner pro Port**.

## 2. Invarianten (Harte Regeln)

1.  **8081 gehört Pi-hole FTL:** Dieser Port ist durch das Pi-hole Webinterface (Host-Mode) belegt. Weltgewebe darf 8081 nicht nutzen.
2.  **Unpublished by Default:** Applikations-Dienste (API, DB) binden **keine** Host-Ports. Sie kommunizieren nur intern im Docker-Netzwerk.
3.  **Gateway-Exklusivität:** Port 80/443 gehören exklusiv dem Edge-Gateway (Caddy). Kein Doppel-Proxy.
4.  **Localhost-Binding:** Wenn ein optionaler Host-Port für Applikationen nötig ist (z.B. Debugging/Health), muss dieser an `127.0.0.1` gebunden werden (nicht `0.0.0.0`).

## 3. Port-Matrix (Host-Namespace)

| Service | Port | Proto | Bind | Zweck | Owner |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SSH** | 22 | TCP | 0.0.0.0 / WG-IP | Admin-Zugang | System (sshd) |
| **WireGuard** | 51820 | UDP | 0.0.0.0 | VPN Tunnel | Kernel (wg) |
| **DNS** | 53 | TCP/UDP | 0.0.0.0 | DNS Resolver | Pi-hole (FTL) |
| **Pi-hole Web** | 8081 | TCP | 0.0.0.0 | Admin Interface | Pi-hole (FTL) |
| **Edge HTTP** | 80 | TCP | 0.0.0.0 | Redirect / ACME | Edge Caddy |
| **Edge HTTPS** | 443 | TCP | 0.0.0.0 | TLS Termination | Edge Caddy |
| **Edge QUIC** | 443 | UDP | 0.0.0.0 | HTTP/3 (Optional) | Edge Caddy |
| **Weltgewebe GW**| 9081 | TCP | 127.0.0.1 | Health / Local Ingress | Weltgewebe (Optional) |
| **Postgres** | 5432 | TCP | - | **Intern (kein Publish)** | Weltgewebe DB |
| **API** | 8080 | TCP | - | **Intern (kein Publish)** | Weltgewebe API |

## 4. Erläuterung der Zuweisung

### 4.1 Pi-hole (Host-Mode)
Da Pi-hole im `network_mode: host` läuft, um Client-IPs zu sehen, belegt es Ports direkt am Interface.
*   **Konflikt:** Standardmäßig will Pi-hole Port 80.
*   **Lösung:** Pi-hole wird auf 8081 (Web) verschoben. Port 53 bleibt DNS.

### 4.2 Edge Caddy (Gateway)
Caddy ist der einzige Prozess, der 80/443 binden darf. Er terminiert TLS und routet intern weiter.
*   Requests an `pihole.heimgewebe.home.arpa` → Caddy (443) → Upstream (localhost:8081).
*   Requests an `api.weltgewebe.home.arpa` → Caddy (443) → Upstream (weltgewebe-api:8080).

### 4.3 Weltgewebe (Applikation)
Weltgewebe ist eine Applikation, keine Infrastruktur.
*   **API (8080):** Bleibt im Docker-Netzwerk. Kein Host-Port.
*   **Health Checks:** Werden primär über Docker-Health (`docker inspect`) oder interne Curls gelöst.
*   **Optionales Gateway (9081):** Falls ein HTTP-Einstiegspunkt für lokale Tools (z.B. `curl` vom Host) nötig ist, wird Port 9081 verwendet. **Niemals 8081.**

## 5. Diagnose & Drift-Erkennung

Prüfen der Invarianten:

```bash
# 1. Prüfen auf unerlaubte Listener (z.B. Postgres auf Host)
sudo ss -lntup | grep -E ":(5432|8080)"
# -> Sollte LEER sein.

# 2. Prüfen der Owner (8081 muss Pi-hole sein)
sudo ss -lntup | grep ":8081"
# -> users:(("pihole-FTL",...))

# 3. Prüfen Gateway Binding (9081 nur auf 127.0.0.1)
sudo ss -lntup | grep ":9081"
# -> 127.0.0.1:9081 ...
```

## 6. Wiederherstellung (Recovery)

Falls Konflikte auftreten (z.B. "Address already in use"):

1.  **Identifizieren:** `sudo ss -lntup -p`
2.  **Entscheiden:** Wer verletzt die Matrix?
    *   Ist es `lighttpd` auf 80? → Pi-hole Config prüfen (`server.port`).
    *   Ist es `postgres` auf 5432? → `ports:` Sektion im Compose-File auf `127.0.0.1` beschränken oder entfernen.
3.  **Korrigieren:** Dienst stoppen, Konfiguration anpassen, Neustart.
