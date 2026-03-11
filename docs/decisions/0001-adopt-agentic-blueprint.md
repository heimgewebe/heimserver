---
id: docs.decisions.0001
title: Adopt Agentic Blueprint
doc_type: decision
role: norm
status: active
canonicality: canonical
last_reviewed: 2026-03-11
summary: Architectural decision to restructure the repository according to the ideal blueprint for agent-ready repositories.
depends_on:
  - docmeta.schema
  - glossary
---

# 0001: Adopt Agentic Blueprint

## Kontext
Das Repository war strukturell gut aufgebaut, jedoch primär für menschliche Operator lesbar. Agents mussten sich aus Prosa-Texten zusammensuchen, wo die Grenzen liegen, welche Dateien verwaist sind und welche Skripte kritisch sind.

## Entscheidung
Wir haben uns entschieden, die "Ideale Blaupause für agentenfreundliche, selbstordnende und selbstverlinkende Repos" zu übernehmen. Das erfordert formelle Verträge, maschinenlesbare Policy-Dateien und generierte Orientierungs- und Entdeckungsmechanismen.

## Alternativen
- **Status Quo beibehalten**: Hätte bedeutet, dass jeder Agent bei jedem Checkout neu aus den Texten inferieren muss, welche Regeln gelten. Skaliert schlecht, besonders bei Delegation.
- **Nur `AGENTS.md` schreiben**: Ein langer Text in `AGENTS.md` ist hilfreich, veraltet aber ohne strukturierte Kopplung (wie `manifest/repo-index.yaml` und Generatoren) und meldet keine "Orphans".

## Folgen
- Neue Markdown-Dateien müssen ab sofort Frontmatter tragen, sonst scheitert die CI (`check-repo-index-consistency.sh`).
- Jeder kritische Operator-Code muss in `audit/impl-registry.yaml` dokumentiert sein.
- Die Generierungsskripte unter `scripts/` sind fester Bestandteil der CI/CD vor einem Merge.

## Betroffene Pfade
- `repo.meta.yaml`
- `agent-policy.yaml`
- `manifest/repo-index.yaml`
- `docs/_generated/`
- `audit/impl-registry.yaml`

## Betroffene Dokumente
- Alle kanonischen Dokumente (`architecture/`, `runtime/`, `runbooks/`).
