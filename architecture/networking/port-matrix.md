# Port-Matrix Heimserver & Gateway-Ownership

**Dokumentklasse:** ARCHITEKTUR · INVARIANTE
**Stand:** 2026-02-25
**Scope:** Host-Namespace Ports (TCP/UDP)

---

## 1. Zielbild: Ein Port, Ein Owner, Ein Zweck

Jeder Port auf dem Heimserver hat genau einen definierten Owner und Zweck. Konflikte werden durch Zuweisung (Pi-hole) oder Isolation (Localhost-Binding) gelöst.

## 2. Invarianten (Harte Regeln)

1.  **8081 gehört Pi-hole FTL:** Reserviert für das Pi-hole Webinterface im Host-Mode. **Verboten für Weltgewebe.**
2.  **9081 ist Edge-Diagnose:** Reserviert für lokalen Caddy-Admin/Metrics Zugriff (nur `127.0.0.1`). **Verboten als App-Ingress.**
3.  **80/443 gehören Edge-Gateway:** Exklusiver Ingress.
4.  **Apps sind Internal:** Weltgewebe-Apps (API, DB) binden standardmäßig **keine** Host-Ports.

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
| **Edge Diag** | 9081 | TCP | **127.0.0.1** | Local Metrics/Health | Edge Caddy |
| **Weltgewebe** | - | - | - | **Intern (kein Publish)** | Weltgewebe |

## 4. Erläuterung der Zuweisung

### 4.1 Pi-hole (8081)
Pi-hole läuft im Host-Mode. Da Port 80 durch Caddy belegt ist, weicht Pi-hole auf 8081 aus.
*   **Prüfung:** `sudo ss -ltnp | grep :8081` → `users:(("pihole-FTL",...))`

### 4.2 Edge Diag (9081)
Dient der Diagnose des Edge-Gateways vom Host aus (z.B. `curl localhost:9081/metrics`).
*   **Bindung:** Zwingend `127.0.0.1`. Niemals `0.0.0.0`.
*   **Prüfung:** `sudo ss -ltnp | grep :9081` → `127.0.0.1:9081`

### 4.3 Weltgewebe (Internal)
Keine Host-Ports. Health-Checks erfolgen via Docker Health (`docker inspect`).
*   **Prüfung:** `sudo ss -ltnp | grep -E ":(8080|5432)"` → Leer.

## 5. Diagnose & Drift-Erkennung

```bash
# Invariante Check
# 1. 8081 muss Pi-hole sein
sudo ss -lntup | grep ":8081"
# -> pihole-FTL

# 2. 9081 muss localhost sein (falls aktiv)
sudo ss -lntup | grep ":9081"
# -> 127.0.0.1:9081

# 3. Keine App-Ports
sudo ss -lntup | grep -E ":(8080|5432)"
# -> (leer)
```

## 6. Wiederherstellung (Recovery)

*   **8081 Konflikt:** Pi-hole Konfiguration prüfen (`/etc/pihole/pihole-FTL.conf` oder Docker Env `WEB_PORT`).
*   **9081 Exposed:** Caddy Compose prüfen – muss `127.0.0.1:9081:9081` sein.
