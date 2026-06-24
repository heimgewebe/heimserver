# Edge Synchronization Runbook
⛔️ OPERATIONAL RUNBOOK

**Target:** `/opt/heimgewebe/edge`
**Source:** `edge/` (Repo Template)

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

**Compose terminology:** The Compose service ID is `caddy`; the stable container name is `edge-caddy`. Use `caddy` with `docker compose` subcommands such as `exec` and `ps`. Use `edge-caddy` only with container-level commands such as `docker inspect` or `docker logs`.

```bash
# Copy Docker Compose
sudo cp edge/docker-compose.yml.template /opt/heimgewebe/edge/docker-compose.yml

# Caddyfile Sync (Three-State-Sync)
# This will perform hash checks, candidate validation, backup, and in-place sync.
# Provide the known good hash of the active file to authorize the sync:
sudo EXPECTED_LIVE_SHA256="<your-reviewed-hash>" bash scripts/edge/sync_caddyfile.sh
```

### 4. Customize Runtime (If needed)
If the specific deployment requires modifications (e.g. specific volume mappings or environment variables), create a `docker-compose.override.yml` on the host. **Do not commit overrides to the repo.**

### 5. Apply Configuration
Reload Caddy to apply changes without downtime. Only execute this after all validation and hash checks pass.

**Reload Safety & Admin Boundary:**
* Reload benötigt die containerlokale Admin-API.
* Erwartete Bindung: `localhost:2019` innerhalb des Containers.
* Compose darf Port 2019 nicht veröffentlichen.
* Host und Container-Netz dürfen Port 2019 nicht erreichen.
* Vor Sync und Reload Admin-Boundary prüfen (wird durch `sync_caddyfile.sh` via `check_admin_boundary.sh` automatisch erzwungen).
* Bei fehlender Admin-API nicht reloaden; stoppen.
* Ein zukünftiges `admin off` erfordert einen separaten Architekturwechsel auf Neustartbetrieb einschließlich neuem Rollback-Verfahren.

```bash
cd /opt/heimgewebe/edge

# Reload config
sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec -T caddy \
  caddy reload \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile
```

### 6. Export Root CA (Post-Deployment)
The internal Root CA is generated inside the `edge_caddy_data` volume. To trust it on clients, export it to the host:

```bash
# Copy root.crt from volume via container execution
sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy cat /data/caddy/pki/authorities/local/root.crt | sudo tee /opt/heimgewebe/edge/certs/caddy-local-root.crt >/dev/null
```
*Note: Path inside container depends on Caddy version/config. If `cat` fails, inspect `/data`.*

## Verification

1.  **Container Status:**
    ```bash
    sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml ps
    # Expect: edge-caddy Up
    ```

2.  **Health Check (Local):**
    ```bash
    sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml ps caddy
    # Expect: Up

    sudo docker logs edge-caddy | tail -n 50
    # Expect: "autosaved config", no errors

    # Optional (if container runs):
    sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy caddy validate --config /etc/caddy/Caddyfile
    ```

3.  **Public Endpoint (Network):**
    ```bash
    curl -I https://weltgewebe.home.arpa
    # Expect: 200 OK or 308 Redirect (depending on path)
    # Check for valid TLS certificate (Internal CA)
    ```

4.  **Upstream Connectivity (Diagnostic):**
    ```bash
    # Verify that 'weltgewebe-api' resolves. If this fails, API routing will break.
    sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec caddy getent hosts weltgewebe-api || echo "WARNING: Upstream 'weltgewebe-api' not resolvable! Fix in Weltgewebe compose."
    ```

## Rollback
If the new configuration fails or post-sync checks abort:
1. Identify the backup file (e.g., `/opt/heimgewebe/edge/Caddyfile.bak.20260623T...`).
2. Read the backup hash: `BACKUP_SHA256="$(sudo sha256sum "$BACKUP_FILE" | awk '{print $1}')"`
3. Restore the configuration into the existing file to preserve the bind-mount inode:
   `sudo sh -c "cat '$BACKUP_FILE' > /opt/heimgewebe/edge/Caddyfile"`
4. Verify host file matches backup hash.
5. Verify container file matches backup hash (`sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec -T caddy sha256sum /etc/caddy/Caddyfile`).
6. Validate container configuration before reload:
   `sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec -T caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile`
7. Reload Caddy:
   `sudo docker compose --project-directory /opt/heimgewebe/edge -f /opt/heimgewebe/edge/docker-compose.yml exec -T caddy caddy reload --adapter caddyfile --config /etc/caddy/Caddyfile`
8. Check logs and health status. Document the failure and the restored backup.

## Drift Management
Any permanent change to the `Caddyfile` on the host MUST be backported to `edge/Caddyfile.template` in the repository, unless it contains secrets.
