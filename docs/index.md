---
id: docs.index
role: norm
status: canonical
last_reviewed: 2026-02-18
depends_on: []
verifies_with:
  - scripts/ci/check-repo-index-consistency.sh
---

# Heimserver Document Index

Dieser Index dient als primärer, kanonischer Doku-Einstieg für den Heimserver.
Er verweist auf die wichtigsten Wahrheitsschichten und das generierte Observatorium.

## Kanonische Wahrheitsquellen

- [README.md](../README.md): Menschlicher Einstieg.
- [AGENTS.md](../AGENTS.md): Agentischer Einstieg und Arbeitsgrenzen.
- [repo.meta.yaml](../repo.meta.yaml): Maschinenlesbare Repo-Struktur.
- [manifest/repo-index.yaml](../manifest/repo-index.yaml): Die deklarative Zone-Zuordnung.

## Dokumentgruppen

Das Repository ist in streng getrennte Zonen (Wahrheitsschichten) unterteilt:

- **Norm (Soll):** `architecture/` - Hier steht, wie das System sein muss.
- **Reality (Ist):** `runtime/` - Hier steht, was aktuell läuft.
- **Action (Tun):** `operations/` - Protokolle und operative Eingriffe.
- **Runbooks:** `runbooks/` - Konkrete Handlungsanweisungen.

## Repo Observatorium

Diese Übersicht wird automatisch aus der Repo-Struktur und den Frontmatter-Daten generiert:

- [docs/_generated/system-map.md](_generated/system-map.md): Zeigt die deklarative Zonen-Übersicht.
- [docs/_generated/doc-index.md](_generated/doc-index.md): Listet alle entdeckten Kanonischen Dokumente.
- [docs/_generated/orphans.md](_generated/orphans.md): Listet Dokumente ohne ausreichende Einordnung.
- [docs/_generated/impl-index.md](_generated/impl-index.md): Listet kritische Implementierungen aus der Registry.
