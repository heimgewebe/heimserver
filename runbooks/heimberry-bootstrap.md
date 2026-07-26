---
id: runbook-heimberry-bootstrap
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Heimberry Bootstrap Runbook
summary: Minimaler Bootstrap für Heimberry als Truth Layer
last_reviewed: 2026-07-26
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/nodes/heimberry.md
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

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
