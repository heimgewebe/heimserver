---
id: runbook-dns-migration
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: DNS Migration Runbook (Heimserver -> Heimberry)
summary: Migrationsablauf für die DNS-Truth-Autorität auf Heimberry
last_reviewed: 2026-04-28
depends_on:
  - architecture/heimnetz-2026.md
  - runtime/runtime.md
verifies_with:
  - ops/checks/preflight.sh
---

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
