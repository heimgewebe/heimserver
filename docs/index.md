---
id: docs.index
title: Canonical Documentation Index
doc_type: reference
role: docs
doc_role: entry
status: active
canonicality: canonical
last_reviewed: 2026-07-26
summary: Zentrale Einstiegsseite in die historische Heimserver-Betriebs- und Vertragsreferenz.
---

# Heimnetz Documentation Index (Repo: `heimserver`)

Dieses Dokument erschließt historische Heimserver-Architektur, Runtime-Belege und Runbooks. Es ist keine Betriebsanleitung für einen aktiven Host. Der aktuelle Zielzustand liegt in der Infra-Verfassung; Heimserver ist außer Betrieb.

## 📖 Lesereihenfolge
1. **[Architektur & Norm](#architektur--norm)** - Verstehe die Regeln, Netzwerke und Kern-Konzepte.
2. **[Runtime & Realität](#runtime--realität)** - Betrachte zeitgebundene historische Beobachtungen, nicht den aktuellen Systemzustand.
3. **[Operationen & Runbooks](#operationen--runbooks)** - Lies frühere Handlungsabläufe ausschließlich als historische Evidenz.
4. **[Entscheidungen (Decisions)](#entscheidungen-decisions)** - Erfahre das "Warum" hinter Änderungen am System.

## 🧭 Generierte Orientierung

Diese maschinell generierten Übersichten bilden strukturierte Sichtweisen auf das Repository ab:
- **[System Map](../SYSTEM_MAP.md):** Die kanonische Übersicht über alle Zonen und verifizierten Dokumente.
- **[Document Index](_generated/doc-index.md):** Eine tabellarische Übersicht aller gefundenen Dokumente im Repo.
- **[Implementations Index](_generated/impl-index.md):** Liste der kritischen Skripte und Checks.
- **[Backlinks](_generated/backlinks.md):** Zeigt, welche Dokumente von welchen abhängig sind.
- **[Orphans](_generated/orphans.md):** Entdeckte Dokumente, die nicht ordentlich im Manifest referenziert wurden.
- **[Supersession Map](_generated/supersession-map.md):** Historie von veralteten Dokumenten.

## 🔭 Repo Observatorium

Das Observatorium liefert generierte Übersichten zum agentischen Gesundheitszustand und zur Wahrheitstreue dieses Repositories:
- **[Architecture Drift](_generated/architecture-drift.md):** Zeigt, wo die reale Pfadstruktur von der dokumentierten abweicht.
- **[Doc Coverage](_generated/doc-coverage.md):** Zeigt, welche kritischen Implementierungen unzureichend dokumentiert sind.
- **[Knowledge Gaps](_generated/knowledge-gaps.md):** Legt implizite Leerstellen in Operationen und Terminologie offen.
- **[Agent Readiness](_generated/agent-readiness.md):** Bewertet die Reife des Repositories in Bezug auf Delegierbarkeit.

## 🏗️ Kern-Dokumentgruppen

### Architektur & Norm
Hier stehen die früheren Regeln und Begründungen. Sie sind durch die aktuelle Infra-Verfassung supersediert.
- [Constitution](../architecture/constitution.md)
- [Naming Conventions](../architecture/naming.md)
- [Network Layout](../architecture/network.md)
- [Port Matrix](../architecture/networking/port-matrix.md)
- [Glossary](../architecture/glossary.md)
- [Heimnetz 2026+](../architecture/heimnetz-2026.md)
- [Node: Heimberry (Truth Layer)](../architecture/nodes/heimberry.md)
- [Node: Heimserver (Service Layer)](../architecture/nodes/heimserver.md)
- [Node: Heim-PC (Interaction Layer)](../architecture/nodes/heim-pc.md)
- [Node: iPad (Access Layer)](../architecture/nodes/ipad.md)

### Runtime & Realität
Hier liegen zeitgebundene Snapshots früherer Laufzustände; sie belegen keinen heutigen Betrieb.
- [Runtime Status](../runtime/runtime.md)
- [Runtime Draft: Heimberry](../runtime/heimberry.md) *(derived/experimental, bis Snapshot-Belege vorliegen)*
- [Runtime Draft: Heimserver](../runtime/heimserver.md) *(derived/experimental, bis Snapshot-Belege vorliegen)*

### Operationen & Runbooks
Hier stehen frühere Eingriffe. Ohne neuen dienstgebundenen Vertrag dürfen sie nicht ausgeführt werden.
- [Operations Policy](../operations/operations.md)
- [Runbooks Index](../runbooks/index.md)

### Entscheidungen (Decisions)
Wenn wir das System grundlegend ändern, dokumentieren wir hier warum.
- [0001: Adopt Agentic Blueprint](decisions/0001-adopt-agentic-blueprint.md)

### Archiv-/Historisierungslogik
Überholte Dokumente bleiben erhalten, werden als `deprecated` oder `archived` markiert und referenzieren mithilfe von `supersedes` oder `deprecated_by` ihre Vorgänger und Nachfolger. Veraltete Implementierungen werden ebenfalls historisiert, anstatt gelöscht zu werden. Dies stellt sicher, dass historische Begründungen verstanden werden können. Details dazu finden sich in der generierten [Supersession Map](_generated/supersession-map.md).
