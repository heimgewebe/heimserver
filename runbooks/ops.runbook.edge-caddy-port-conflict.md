---
id: ops.runbook.edge-caddy-port-conflict
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: Caddy Port Conflict Runbook
summary: Steps to resolve Caddy port conflicts
last_reviewed: 2026-02-25
depends_on:
  - architecture/networking/port-matrix.md
  - runbooks/index.md
verifies_with:
  - ops/checks/preflight.sh
---

# ops.runbook.edge-caddy-port-conflict

## 1. Incident summary
The edge gateway (Caddy container) failed to start due to a port conflict with Pi-hole.

## 2. Symptoms
The edge stack runs in:
`/opt/heimgewebe/edge`

During deployment the container failed with:
`failed to bind host port for 127.0.0.1:8081`
`address already in use`

The container remained in "Created" state and never bound ports 80/443, causing the gateway to appear offline.

## 3. Diagnosis steps
Change to the stack directory:
```bash
cd /opt/heimgewebe/edge
```

Commands used during diagnosis:
```bash
sudo ss -tulpn | grep 8081
rg 8081 docker-compose.override.yml # if present on host
```

Observed state:
`0.0.0.0:8081 users:(("pihole-FTL"))`

Compose configuration (e.g., in a host-local override):
`127.0.0.1:8081:8081`

## 4. Root cause
Pi-hole already binds port 8081 globally (0.0.0.0:8081), which prevents Docker from binding 127.0.0.1:8081.

## 5. Fix
Remove any `127.0.0.1:8081:8081` host port mapping from the edge Compose configuration on the host (for example from `docker-compose.override.yml`, if present).

Restart the stack from the correct directory:
```bash
cd /opt/heimgewebe/edge
```

```bash
docker compose down
docker compose up -d
```

## 6. Prevention rule
Architecture rule: Edge gateway should only expose ports required for ingress:
`80`
`443`

Do not add debug/admin ports to the edge gateway.

## 7. Architecture lesson
Edge gateway = minimal ports. Everything else does not belong in the edge-layer.
