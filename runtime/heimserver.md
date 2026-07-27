---
id: runtime-heimserver
role: reality
status: deprecated
canonicality: explanatory
doc_type: experimental
title: Historical Runtime Draft - Heimserver (Service Layer)
summary: Historische Nachweisvorlage für die frühere Heimserver-Runtime
last_reviewed: 2026-07-26
depends_on:
  - architecture/heimnetz-2026.md
  - architecture/nodes/heimserver.md
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historical Runtime Heimserver Draft (non-canonical reference)

## Scope
Frühere Zielbeschreibung der Heimserver-Laufzeit im damaligen Service-Layer-Modell.

## Frühere Invarianten des damaligen Zielmodells
- Heimserver betreibt kein primäres DNS.
- Heimserver betreibt keinen VPN-Core.
- Servicezugriff erfolgt über Caddy/FQDN statt Direktports.

## Nachweisstatus
Die bisherige monolithische Runtime ist in [`runtime.md`](runtime.md) als historical/migration-state dokumentiert.
Dieses Dokument war als Strukturvorlage vorgesehen. Es darf im retired Repository nicht als aktuelle Runtime-Quelle aufgewertet werden.
