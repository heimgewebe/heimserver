---
id: runbooks-index
role: runbooks
doc_role: entry
status: deprecated
canonicality: explanatory
doc_type: reference
title: Runbooks Index
summary: Entrypoint for execution guides
last_reviewed: 2026-07-26
depends_on: []
verifies_with:
  - scripts/ci/check-runbook-invariants.sh
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

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

## Weltgewebe Public Edge
- `weltgewebe-dyndns.md` — outbound-only DynDNS auf Heimberry für die drei erlaubten Public-Hosts

## Historical / Superseded
- `ops.runbook.heimserver-edge.md` — superseded (monolithisches Altmodell)
- `dns-pihole-wildcard.md` — superseded (Heimserver-DNS-Altpfad)

## Common Deployment Failures
- [`ops.runbook.edge-caddy-port-conflict.md`](ops.runbook.edge-caddy-port-conflict.md) — Edge gateway fails to start due to port conflicts (8081)
