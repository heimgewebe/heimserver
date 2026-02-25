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

### 2. Synchronize Templates
Copy the templates to the host and remove the `.template` extension.
**Warning:** Do not overwrite existing certificates or data volumes.

```bash
# Copy Docker Compose
cp edge/docker-compose.yml.template /opt/heimgewebe/edge/docker-compose.yml

# Copy Caddyfile (Review changes first!)
# If a Caddyfile already exists, diff it first.
diff edge/Caddyfile.template /opt/heimgewebe/edge/Caddyfile || echo "Drift detected"
cp edge/Caddyfile.template /opt/heimgewebe/edge/Caddyfile
```

### 3. Customize Runtime (If needed)
If the specific deployment requires modifications (e.g. specific volume mappings or environment variables), create a `docker-compose.override.yml` on the host. **Do not commit overrides to the repo.**

### 4. Apply Configuration
Reload Caddy to apply changes without downtime.

```bash
cd /opt/heimgewebe/edge
docker compose up -d
# Or just reload config if container is running:
docker compose exec edge-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Verification

1.  **Container Status:**
    ```bash
    docker compose ps
    # Expect: edge-caddy Up
    ```

2.  **Health Check (Local):**
    ```bash
    curl -f http://127.0.0.1:8081/health/ready
    # Expect: OK
    ```

3.  **Public Endpoint (Network):**
    ```bash
    curl -I https://weltgewebe.home.arpa
    # Expect: 200 OK or 308 Redirect (depending on path)
    # Check for valid TLS certificate (Internal CA)
    ```

## Rollback
If the new configuration fails:
1.  Revert `Caddyfile` to the previous version (if backed up).
2.  `docker compose exec edge-caddy caddy reload --config /etc/caddy/Caddyfile`
3.  Check logs: `docker compose logs edge-caddy`

## Drift Management
Any permanent change to the `Caddyfile` on the host MUST be backported to `edge/Caddyfile.template` in the repository, unless it contains secrets.
