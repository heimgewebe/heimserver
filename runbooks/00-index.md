---
id: runbooks-index
role: runbooks
status: canonical
last_reviewed: 2026-02-13
depends_on: []
verifies_with:
  - scripts/ci/check-runbook-invariants.sh
---

# Runbooks Index

Diese Runbooks sind operative Abläufe (Recovery/Rotation/Änderungen).

## Basis
- `10-preflight.md` — Checks vor/nach Änderungen

## Security
- `30-wireguard-rotation.md` — Rotation / Neuaufsetzen ohne Keys in Git
- `31-pki-rotation.md` — Caddy internal CA / PKI Rotation (ohne private keys in Git)

## Common Deployment Failures
- [`ops.runbook.edge-caddy-port-conflict.md`](ops.runbook.edge-caddy-port-conflict.md) — Edge gateway fails to start due to port conflicts (8081)
