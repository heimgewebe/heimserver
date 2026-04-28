---
id: node-heimberry
role: norm
status: active
canonicality: canonical
doc_type: architecture
title: Node Role - Heimberry (Truth Layer)
summary: Verbindliche Rollenbeschreibung für Heimberry als DNS/Truth-Knoten
last_reviewed: 2026-04-28
depends_on:
  - heimnetz-2026
verifies_with: []
---

# Heimberry — Truth Layer

## Rolle (kanonisch)
- Primärer und einziger Truth-Knoten für DNS im Heimnetz (`home.arpa`)
- Pi-hole + Unbound + Tailscale DNS-Integration

## Explizit ausgeschlossen
- Kein Reverse Proxy
- Keine App-Container
- Keine Dev-Primärumgebung

## Migrationshinweis
Dieses Dokument operationalisiert die Zielarchitektur aus `architecture/heimnetz-2026.md`.
