---
id: runbook-heimberry-bootstrap
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: Heimberry Bootstrap Runbook
summary: Minimaler Bootstrap für Heimberry als Truth Layer
last_reviewed: 2026-04-28
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/nodes/heimberry.md
verifies_with:
  - ops/checks/preflight.sh
---

# Heimberry Bootstrap (Truth Layer)

## Ziel
Heimberry als kanonischen DNS-/Truth-Knoten betriebsbereit machen.

## Minimalablauf
1. Basis-Host bereitstellen (OS + Netzwerk).
2. Pi-hole + Unbound bereitstellen.
3. Tailscale aktivieren und DNS-Pfad auf Heimberry ausrichten.
4. DNS-Checks gegen Heimberry durchführen (`dig @<heimberry-ip> ...`).

## Guardrails
- Kein Dual-DNS im DHCP als gleichrangige Wahrheit.
- Keine Secrets im Repo.
