---
id: runbooks-index
role: runbooks
doc_role: entry
status: active
canonicality: canonical
doc_type: reference
title: Runbooks Index
summary: Entrypoint for execution guides
last_reviewed: 2026-04-28
depends_on: []
verifies_with:
  - scripts/ci/check-runbook-invariants.sh
---

# Runbooks Index

Diese Runbooks sind operative Abläufe (Recovery/Rotation/Änderungen).

## Basis
- `preflight.md` — Checks vor/nach Änderungen

## Security
- `wireguard-rotation.md` — **historical/migration-state** (Legacy-Referenz)
- `pki-rotation.md` — Caddy internal CA / PKI Rotation (ohne private keys in Git)

## Migration (Layer-Modell)
- `heimberry-bootstrap.md` — Truth-Layer Bootstrap für Heimberry
- `dns-migration.md` — DNS-Autorität von Heimserver nach Heimberry verlagern
- `tailscale-migration.md` — Overlay-Migration auf Tailscale als Zielmodell

## Historical / Superseded
- `ops.runbook.heimserver-edge.md` — superseded (monolithisches Altmodell)
- `dns-pihole-wildcard.md` — superseded (Heimserver-DNS-Altpfad)

## Common Deployment Failures
- [`ops.runbook.edge-caddy-port-conflict.md`](ops.runbook.edge-caddy-port-conflict.md) — Edge gateway fails to start due to port conflicts (8081)
