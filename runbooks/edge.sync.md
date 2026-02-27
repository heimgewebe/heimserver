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
sudo mkdir -p /opt/heimgewebe/edge/html
sudo chown -R root:root /opt/heimgewebe/edge
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

```bash
# Copy Docker Compose
cp edge/docker-compose.yml.template /opt/heimgewebe/edge/docker-compose.yml

# Copy Caddyfile (Check Drift!)
# If a Caddyfile already exists, diff it first.
if diff edge/Caddyfile.template /opt/heimgewebe/edge/Caddyfile >/dev/null; then
    echo "No Caddyfile drift."
else
    echo "DRIFT DETECTED in Caddyfile!"
    diff edge/Caddyfile.template /opt/heimgewebe/edge/Caddyfile
    echo "Review diff. If intentional host-changes, backport to template."
    echo "To force overwrite: cp edge/Caddyfile.template /opt/heimgewebe/edge/Caddyfile"
    # exit 1 # Uncomment in CI/Strict mode
fi
```

### 4. Customize Runtime (If needed)
If the specific deployment requires modifications (e.g. specific volume mappings or environment variables), create a `docker-compose.override.yml` on the host. **Do not commit overrides to the repo.**

### 5. Apply Configuration
Reload Caddy to apply changes without downtime.

```bash
cd /opt/heimgewebe/edge
docker compose up -d
# Or just reload config if container is running:
docker compose exec edge-caddy caddy reload --config /etc/caddy/Caddyfile
```

### 6. Export Root CA (Post-Deployment)
The internal Root CA is generated inside the `edge_caddy_data` volume. To trust it on clients, export it to the host:

```bash
# Copy root.crt from volume via container execution
docker compose exec edge-caddy cat /data/caddy/pki/authorities/local/root.crt > /opt/heimgewebe/edge/certs/caddy-local-root.crt
```
*Note: Path inside container depends on Caddy version/config. If `cat` fails, inspect `/data`.*

## Verification

1.  **Container Status:**
    ```bash
    docker compose ps
    # Expect: edge-caddy Up
    ```

2.  **Health Check (Local):**
    ```bash
    # Diagnostic only (if active in Caddyfile):
    curl -f http://127.0.0.1:9081/health/ready
    # Expect: OK or Connection Refused (if disabled)

    # Primary Check:
    docker compose ps edge-caddy
    docker logs edge-caddy | tail -n 20
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
    docker compose exec edge-caddy getent hosts weltgewebe-api || echo "WARNING: Upstream 'weltgewebe-api' not resolvable! Fix in Weltgewebe compose."
    ```

## Rollback
If the new configuration fails:
1.  Revert `Caddyfile` to the previous version (if backed up).
2.  `docker compose exec edge-caddy caddy reload --config /etc/caddy/Caddyfile`
3.  Check logs: `docker compose logs edge-caddy`

## Drift Management
Any permanent change to the `Caddyfile` on the host MUST be backported to `edge/Caddyfile.template` in the repository, unless it contains secrets.
