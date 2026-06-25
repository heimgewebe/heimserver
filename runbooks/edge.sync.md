# Edge Synchronization Runbook
⛔️ OPERATIONAL RUNBOOK

**Target:** `/opt/heimgewebe/edge`
**Source:** `edge/` (Repo Template)

## Sync Gate-Reihenfolge (`sync_caddyfile.sh`)

Die folgenden Gates werden in dieser zwingenden Reihenfolge ausgeführt.
Ein Fehlschlag an einem Gate bricht den Sync sofort ab — keine Mutation findet statt.

| Gate | Was wird geprüft | Exit bei Fehler |
|------|-----------------|-----------------|
| 1. Hash + Container-Identität | `sha256sum` der Live-Datei muss mit `EXPECTED_LIVE_SHA256` übereinstimmen; Container-Datei muss mit Host übereinstimmen | 1 |
| 2. Snapshot + Caddy-Syntax (`caddy validate`) | Ein privater Snapshot des Kandidaten ist syntaktisch korrekt; der veränderliche Quellpfad wird danach nicht mehr geschrieben | ≠0 (Docker exit code) |
| 3. Snapshot-Verträge | `validate_caddy_contract.py` und `validate_caddy_redirect.py` prüfen Admin-Binding, Hosts, Upstream, Cache, CSP, Route-Reihenfolge und den exakten Redirect `/api` → `/api/` | 1 = Vertrag verletzt, 2 = Diagnose nicht möglich |
| 4. Aktive Admin-Boundary (`check_admin_boundary.sh`) | Genau eine Compose-Container-ID; Admin-API auf IPv4- oder IPv6-Loopback erreichbar; Port 2019 weder in Compose noch im Runtime-Container oder Host veröffentlicht | 1 = Vertrag verletzt, 2 = Diagnose nicht möglich |
| 5. Live-TOCTOU-Wiederholung | Hash-Check der Live-Datei unmittelbar vor dem Schreiben | 1 |
| 6. Backup + Write | `cp -a` sichert die Live-Datei; ausschließlich der validierte Snapshot wird in-place geschrieben | 1 oder 255 bei Rollback-Fehler |

### Exit-Codes

| Exit | Bedeutung |
|------|-----------|
| 0 | Sync erfolgreich, Live-Datei aktualisiert |
| 1 | Vertrag verletzt oder Drift erkannt — keine Mutation |
| 2 | Diagnose nicht möglich (fehlendes Tool, ungültiges JSON, kein Container) |
| 255 | Rollback nicht vollständig verifiziert — manueller Eingriff erforderlich |

> [!IMPORTANT]
> `sync_caddyfile.sh` führt **keinen** `caddy reload` durch. Nach erfolgreichem Sync muss der Reload
> manuell gemäß Schritt 5 „Apply Configuration" ausgeführt werden.

## Context
The Edge service (Caddy) is the primary ingress for `weltgewebe.home.arpa` and `heimgewebe.home.arpa`.
Configuration is managed via templates in this repository to prevent drift, but the actual runtime environment contains state (certificates, data) that must not be committed.

## Deployment Procedure

### 1. Prepare Host Directory
Ensure the directory structure exists on the host:
```bash
sudo mkdir -p /opt/heimgewebe/edge/certs
sudo chown -R root:root /opt/heimgewebe/edge
```

**Note for Weltgewebe Static UI:**
The Edge Caddy requires the external path `/opt/weltgewebe/apps/web/build` to exist to serve the static UI locally.
If this directory does not exist, Docker will automatically create it as `root:root` when starting `edge-caddy`, which will cause permission errors for subsequent Weltgewebe builds.
Before starting the Edge container, ensure the directory exists and has the correct ownership for the actual deployment user on the host.

```bash
sudo mkdir -p /opt/weltgewebe/apps/web/build
# Adjust ownership of the UI build path to match the actual deployment user
# (replace 'myuser:mygroup' with the real user/group on the host)
# sudo chown -R myuser:mygroup /opt/weltgewebe/apps/web/build
```

### 2. Verify External Networks
Ensure required networks exist (create if missing):
```bash
docker network inspect edge || docker network create edge
docker network inspect heimnet || docker network create heimnet
# weltgewebe_default is REQUIRED for API connectivity (edge-caddy sits in it to reach weltgewebe-api)
docker network inspect weltgewebe_default >/dev/null 2>&1 || { echo "CRITICAL: weltgewebe_default missing! Edge compose will fail."; exit 1; }
```

### 3. Synchronize Templates
Copy the templates to the host and remove the `.template` extension.
**Warning:** Do not overwrite existing certificates or data volumes.

**Compose terminology:** The Compose service ID is `caddy`. Guards resolve its current container ID once through `docker compose ps --quiet caddy` and use that exact ID for runtime inspection. The stable name `edge-caddy` remains an operational label, not the guard's identity source.

```bash
# Copy Docker Compose
sudo cp edge/docker-compose.yml.template /opt/heimgewebe/edge/docker-compose.yml

# Caddyfile Sync (Three-State-Sync)
# Performs hash checks, immutable snapshot validation, backup and in-place sync.
sudo EXPECTED_LIVE_SHA256="<your-reviewed-hash>" bash scripts/edge/sync_caddyfile.sh
```

### 4. Customize Runtime (If needed)
If the specific deployment requires modifications (e.g. specific volume mappings or environment variables), create a `docker-compose.override.yml` on the host. **Do not commit overrides to the repo.**

### 5. Apply Configuration
Reload Caddy to apply changes without downtime. Only execute this after all validation and hash checks pass.

**Reload Safety & Admin Boundary:**
* Reload benötigt die containerlokale Admin-API.
* Zulässige Bindungen: `localhost:2019`, `127.0.0.1:2019` oder `[::1]:2019` innerhalb genau des von Compose aufgelösten Containers.
* Compose darf Port 2019 nicht veröffentlichen.
* Host und Container-Netz dürfen Port 2019 nicht erreichen.
* Vor Sync und Reload Admin-Boundary prüfen; `sync_caddyfile.sh` erzwingt dies automatisch.
* Bei fehlender Admin-API nicht reloaden; stoppen.
* Ein zukünftiges `admin off` erfordert einen separaten Architekturwechsel auf Neustartbetrieb einschließlich neuem Rollback-Verfahren.

```bash
cd /opt/heimgewebe/edge
sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec -T caddy \
  caddy reload \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile
```

### 6. Export Root CA (Post-Deployment)
The internal Root CA is generated inside the `edge_caddy_data` volume. To trust it on clients, export it to the host:

```bash
sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy cat /data/caddy/pki/authorities/local/root.crt | sudo tee /opt/heimgewebe/edge/certs/caddy-local-root.crt >/dev/null
```
*Note: Path inside container depends on Caddy version/config. If `cat` fails, inspect `/data`.*

## Verification

1. **Container Status:**
   ```bash
   sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml ps
   ```

2. **Health Check (Local):**
   ```bash
   sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml ps caddy
   sudo docker logs edge-caddy | tail -n 50
   sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy caddy validate --config /etc/caddy/Caddyfile
   ```

3. **Public Endpoint (Network):**
   ```bash
   curl -I https://weltgewebe.home.arpa
   ```

4. **Upstream Connectivity (Diagnostic):**
   ```bash
   sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy getent hosts weltgewebe-api || echo "WARNING: Upstream 'weltgewebe-api' not resolvable! Fix in Weltgewebe compose."
   ```

## Rollback
If the new configuration fails or post-sync checks abort:
1. Identify the backup file.
2. Read its SHA-256.
3. Restore it in-place with `cat` to preserve the bind-mount inode.
4. Verify the host hash.
5. Verify the container hash.
6. Validate the restored container configuration.
7. Reload Caddy only after all rollback checks pass.
8. Check logs and health status and document the failure.

## Drift Management
Any permanent change to the `Caddyfile` on the host MUST be backported to `edge/Caddyfile.template` in the repository, unless it contains secrets.
