---
id: runbook-tailscale-migration
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Historical Tailscale Migration Runbook
summary: Historischer Übergang vom früheren WireGuard-Primärmodell zum Tailscale-Zielmodell
last_reviewed: 2026-07-26
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/network.md
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historische Tailscale-Migration (Primary Overlay)

## Ziel
Früherer Zielzustand: Tailscale als primären Overlay-/Access-Pfad etablieren.

## Minimalablauf
1. Tailscale auf relevanten Knoten/Clients aktivieren.
2. DNS-Integration auf Heimberry sicherstellen.
3. WireGuard nur als historical/migration-state weiterführen.
4. Nach Stabilisierung Legacy-WireGuard kontrolliert ausphasen.

## Guardrails
- Kein Dual-VPN als Dauerzustand.
- Keine implizite Rückkehr zum WireGuard-Primärmodell.
