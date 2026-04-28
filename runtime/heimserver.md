---
id: runtime-heimserver
role: reality
status: experimental
canonicality: derived
doc_type: experimental
title: Runtime Draft - Heimserver (Service Layer)
summary: Nachweisvorlage für Heimserver-Runtime, bis Snapshot-Belege vorliegen
last_reviewed: 2026-04-28
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/nodes/heimserver.md
verifies_with:
  - ops/audit/collect.sh
---

# Runtime Heimserver (Draft / non-canonical reality)

## Scope
Service-Layer-Laufzeitrealität für Heimserver (Caddy, interne PKI, App-Container).

## Invarianten (Zielmodell)
- Heimserver betreibt kein primäres DNS.
- Heimserver betreibt keinen VPN-Core.
- Servicezugriff erfolgt über Caddy/FQDN statt Direktports.

## Nachweisstatus
Die bisherige monolithische Runtime ist in [`runtime.md`](runtime.md) als historical/migration-state dokumentiert.
Dieses Dokument ist eine Strukturvorlage und wird erst mit belegten Outputs (z.B. `ops/audit/collect.sh`) zur kanonischen Runtime erhoben.
