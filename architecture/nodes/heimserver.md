---
id: node-heimserver
role: norm
status: active
canonicality: canonical
doc_type: architecture
title: Node Role - Heimserver (Service Layer)
summary: Verbindliche Rollenbeschreibung für Heimserver als Service-Layer
last_reviewed: 2026-04-28
depends_on:
  - heimnetz-2026
verifies_with: []
---

# Heimserver — Service Layer

## Rolle (kanonisch)
- Service-Host für Caddy, interne PKI und interne Anwendungen
- Monitoring-/Watchdog-Funktion für Heimberry-Verfügbarkeit

## Explizit ausgeschlossen
- Kein primäres DNS
- Kein VPN-Core
- Keine implizite Netzwerkautorität

## Migrationshinweis
WireGuard-bezogene Altpfade werden als `historical` geführt, bis die Migration vollständig abgeschlossen ist.
