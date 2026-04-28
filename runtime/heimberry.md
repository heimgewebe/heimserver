---
id: runtime-heimberry
role: reality
status: experimental
canonicality: derived
doc_type: experimental
title: Runtime Draft - Heimberry (Truth Layer)
summary: Nachweisvorlage für Heimberry-Runtime, bis Snapshot-Belege vorliegen
last_reviewed: 2026-04-28
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/nodes/heimberry.md
verifies_with:
  - ops/audit/collect.sh
---

# Runtime Heimberry (Draft / non-canonical reality)

## Scope
Truth-Layer-Laufzeitrealität für Heimberry (Pi-hole, Unbound, Tailscale DNS-Integration).

## Invarianten (Zielmodell)
- Heimberry ist primärer Resolver für `home.arpa`.
- Kein Dual-DNS als gleichrangige Wahrheit.
- Tailscale DNS zeigt auf Heimberry.

## Nachweisstatus
Dieses Dokument ist eine Strukturvorlage.
Konkrete Runtime-Werte werden nur mit Snapshot-/Audit-Belegen ergänzt; erst dann erfolgt Einstufung als kanonische Reality.
