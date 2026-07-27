---
id: runbook-adding-docs
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: guide
title: Historical Heimserver documentation workflow
summary: Historical record of how canonical Heimserver documents were formerly added
last_reviewed: 2026-07-27
depends_on: []
verifies_with: []
---

# Historical Heimserver documentation workflow

> **Historische Referenz — nicht ausführen.**

This document records the former documentation process of the retired Heimserver repository. It must not be used to create new active or canonical operational documents in `architecture/`, `runtime/`, `operations/`, or `runbooks/`.

Current documentation changes belong in the repository that currently owns the affected system or service. Its own `AGENTS.md`, repository metadata, schemas, review rules, and generators define the applicable workflow.

## Former process

The retired repository previously used the following sequence:

1. A Markdown document was created in a zone selected by its former norm, reality, action, or runbook role.
2. The document received YAML frontmatter and was registered in `manifest/repo-index.yaml`.
3. Repository consistency checks validated the identifier, metadata, and index relationship.
4. Generated indexes and maps were refreshed and committed with the source document.

The former `active` and `canonical` template is intentionally not reproduced here. Copying it into a historical zone would falsely recreate current authority.

## Historical validation references

The static commands retained in this repository validate archival consistency only. They do not authorize operational documentation, runtime changes, deployments, host reads, or service activation.

The repository-wide retirement checker is `scripts/ci/check_retired_reference_contract.py`. Generated files remain derived outputs and must not be edited manually.
