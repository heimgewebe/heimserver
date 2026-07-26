---
id: node-heimberry
role: norm
status: deprecated
canonicality: explanatory
doc_type: architecture
title: Node Role - Heimberry (Truth Layer)
summary: Verbindliche Rollenbeschreibung für Heimberry als DNS/Truth-Knoten
last_reviewed: 2026-07-26
depends_on:
  - heimnetz-2026
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

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
