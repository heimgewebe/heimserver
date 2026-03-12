---
id: docs.index
title: Canonical Documentation Index
doc_type: reference
role: docs
status: active
canonicality: canonical
last_reviewed: 2026-03-11
summary: Zentrale Einstiegs- und Orientierungsseite für die gesamte Dokumentation.
---

# Heimserver Documentation Index

Dieses Dokument bildet den zentralen Einstieg in die strukturierte Dokumentation des Repositories.

## 📖 Lesereihenfolge
1. **[Architektur & Norm](#architektur--norm)** - Verstehe die Regeln, Netzwerke und Kern-Konzepte.
2. **[Runtime & Realität](#runtime--realität)** - Betrachte den aktuellen Systemzustand.
3. **[Operationen & Runbooks](#operationen--runbooks)** - Lerne wie man eingreift und Handlungsabläufe ausführt.
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
Hier stehen die Regeln, nach denen die Infrastruktur zu funktionieren hat. Lese dies, um das "Warum" zu verstehen.
- [Constitution](../architecture/constitution.md)
- [Naming Conventions](../architecture/naming.md)
- [Network Layout](../architecture/network.md)
- [Port Matrix](../architecture/networking/port-matrix.md)
- [Glossary](../architecture/glossary.md)

### Runtime & Realität
Hier dokumentieren wir in Snapshots, wie der Server *tatsächlich* gerade läuft.
- [Runtime Status](../runtime/runtime.md)

### Operationen & Runbooks
Hier steht, wie wir eingreifen, wenn das System drifftet oder Updates braucht.
- [Operations Policy](../operations/operations.md)
- [Runbooks Index](../runbooks/index.md)

### Entscheidungen (Decisions)
Wenn wir das System grundlegend ändern, dokumentieren wir hier warum.
- [0001: Adopt Agentic Blueprint](decisions/0001-adopt-agentic-blueprint.md)

### Archiv-/Historisierungslogik
Überholte Dokumente bleiben erhalten, werden als `deprecated` oder `archived` markiert und referenzieren mithilfe von `supersedes` oder `deprecated_by` ihre Vorgänger und Nachfolger. Veraltete Implementierungen werden ebenfalls historisiert, anstatt gelöscht zu werden. Dies stellt sicher, dass historische Begründungen verstanden werden können. Details dazu finden sich in der generierten [Supersession Map](_generated/supersession-map.md).
