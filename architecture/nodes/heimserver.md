---
id: node-heimserver
role: norm
status: deprecated
canonicality: explanatory
doc_type: architecture
title: Historical Node Role - Heimserver
summary: Historische Rollenbeschreibung des früheren Heimserver-Service-Layers
last_reviewed: 2026-07-26
depends_on:
  - heimnetz-2026
verifies_with: []
---

# Heimserver — historische Service-Layer-Rolle

> **Historische Referenz.** Dieses Dokument beschreibt die frühere Heimserver-Architektur. Heimserver ist außer Betrieb und besitzt keine aktive Rolle, Exposition, Autorität oder Recovery-Abhängigkeit. Der aktuelle Zielzustand liegt in [`heimgewebe/infra@e1245b5…:INFRA_CONSTITUTION.md`](https://github.com/heimgewebe/infra/blob/e1245b502393edcdb42d0f20317c8a5a2c2defbe/INFRA_CONSTITUTION.md). Die folgenden Inhalte dürfen nicht als heutige Betriebsfreigabe gelesen oder ausgeführt werden.


## Frühere Rolle
- Service-Host für Caddy, interne PKI und interne Anwendungen
- Monitoring-/Watchdog-Funktion für Heimberry-Verfügbarkeit

## Explizit ausgeschlossen
- Kein primäres DNS
- Kein VPN-Core
- Keine implizite Netzwerkautorität

## Migrationshinweis
WireGuard-bezogene Altpfade werden als `historical` geführt, bis die Migration vollständig abgeschlossen ist.
