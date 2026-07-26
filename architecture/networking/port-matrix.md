---
id: port-matrix
role: norm
status: deprecated
canonicality: explanatory
doc_type: architecture
title: Port Matrix
summary: Formal port ownership specification
last_reviewed: 2026-07-26
depends_on:
  - architecture/network.md
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Port-Matrix Heimserver & Gateway-Ownership

**Dokumentklasse:** HISTORISCHE ARCHITEKTUR · FRÜHERE INVARIANTE
**Stand:** 2026-02-25
**Scope:** Host-Namespace Ports (TCP/UDP)

---

## 1. Zielbild: Ein Port, Ein Owner, Ein Zweck

Jeder Port auf dem Heimserver hat genau einen definierten Owner und Zweck. Konflikte werden durch Zuweisung (Pi-hole) oder Isolation (Localhost-Binding) gelöst.
Apps und Diagnostics laufen **Internal Only**.

## 2. Invarianten (Harte Regeln)

1.  **8081 gehört Pi-hole FTL:** Reserviert für das Pi-hole Webinterface im Host-Mode. **Verboten für Weltgewebe.**
2.  **Strict Internal Policy:** Apps (API, DB, Gateway, Diagnostics) binden **keine** Host-Ports. Kommunikation erfolgt ausschließlich über Docker-Netzwerke oder `docker exec`.
3.  **80/443 gehören Edge-Gateway:** Exklusiver Ingress.

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
| **Weltgewebe** | - | - | - | **Intern (kein Publish)** | Weltgewebe |

## 4. Erläuterung der Zuweisung

### 4.1 Pi-hole (8081)
Pi-hole läuft im Host-Mode. Da Port 80 durch Caddy belegt ist, weicht Pi-hole auf 8081 aus.
*   **Prüfung:** `sudo ss -ltnp | grep :8081` → `users:(("pihole-FTL",...))`

### 4.2 Weltgewebe & Edge Diagnostics (Internal)
Keine Host-Ports. Health-Checks und Metriken erfolgen via Docker Health (`docker inspect`) oder `docker logs`.
*   **Prüfung:** `sudo ss -ltnp | grep -E ":(8080|5432|9081)"` → Leer.

## 5. Diagnose & Drift-Erkennung

```bash
# Invariante Check
# 1. 8081 muss Pi-hole sein
sudo ss -lntup | grep ":8081"
# -> pihole-FTL

# 2. Keine App-Ports (inkl. 9081)
sudo ss -lntup | grep -E ":(8080|5432|9081)"
# -> (leer)
```

## 6. Wiederherstellung (Recovery)

*   **8081 Konflikt:** Pi-hole Konfiguration prüfen (`/etc/pihole/pihole-FTL.conf` oder Docker Env `WEB_PORT`).
*   **App Exposed:** Docker Compose prüfen – `ports:` Sektion entfernen.
