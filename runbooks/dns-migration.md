---
id: runbook-dns-migration
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: DNS Migration Runbook (Heimserver -> Heimberry)
summary: Migrationsablauf für die DNS-Truth-Autorität auf Heimberry
last_reviewed: 2026-07-26
depends_on:
  - architecture/heimnetz-2026.md
  - runtime/runtime.md
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# DNS Migration: Heimserver → Heimberry

## Ziel
DNS-Truth von Heimserver auf Heimberry verlagern, ohne Dual-Authority.

## Minimalablauf
1. Heimberry DNS-Funktion validieren.
2. Client-/Router-DNS schrittweise auf Heimberry umstellen.
3. Alte Heimserver-DNS-Pfade als historical markieren.
4. Splitbrain-Checks und Drift-Checks ausführen.

## Erfolgsbedingung
`home.arpa` wird kanonisch über Heimberry beantwortet.
