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

## 🧭 Generierte Orientierung

Diese maschinell generierten Übersichten bilden die aktuelle Realität des Repositories ab:
- **[System Map](../SYSTEM_MAP.md):** Die kanonische Übersicht über alle Zonen und verifizierten Dokumente.
- **[Document Index](_generated/doc-index.md):** Eine tabellarische Übersicht aller gefundenen Dokumente im Repo.
- **[Implementations Index](_generated/impl-index.md):** Liste der kritischen Skripte und Checks.
- **[Backlinks](_generated/backlinks.md):** Zeigt, welche Dokumente von welchen abhängig sind.
- **[Orphans](_generated/orphans.md):** Entdeckte Dokumente, die nicht ordentlich im Manifest referenziert wurden.
- **[Supersession Map](_generated/supersession-map.md):** Historie von veralteten Dokumenten.

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
- [Runbooks Index](../runbooks/00-index.md)

### Entscheidungen (Decisions)
Wenn wir das System grundlegend ändern, dokumentieren wir hier warum.
- [0001: Adopt Agentic Blueprint](decisions/0001-adopt-agentic-blueprint.md)
