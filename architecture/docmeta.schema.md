---
id: docmeta.schema
role: norm
status: active
canonicality: canonical
doc_type: policy
title: DocMeta Schema
summary: Definition of canonical metadata schema
last_reviewed: 2026-02-18
depends_on: []
verifies_with:
  - scripts/ci/check-repo-index-consistency.sh
---

# docmeta.schema.md

Definition of the Metadata Schema for Canonical Documentation.

## 1. Frontmatter

Every canonical document must start with a YAML frontmatter block containing the following fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | Yes | Unique identifier for the document (slug). |
| `title` | string | Yes | Human-readable title of the document. |
| `doc_type` | enum | Yes | The type of the document (e.g., architecture, runbook). |
| `role` | enum | Yes | The zone role of the document. |
| `status` | enum | Yes | The lifecycle status (active, deprecated, experimental, archived). |
| `canonicality` | enum | Yes | The authority level (canonical, derived). |
| `last_reviewed` | date | Yes | Date of last significant review (YYYY-MM-DD). |
| `summary` | string | Yes | A short description of the document. |
| `documents` | list | No | Paths or modules this document describes. |
| `implemented_by` | list | No | Code or scripts implementing this document. |
| `depends_on` | list | No | List of files (paths or IDs) this doc depends on. |
| `related_docs` | list | No | Other related documents. |
| `verifies_with` | list | No | List of scripts that verify this document's truth. |
| `supersedes` | list | No | IDs of documents this document replaces. |
| `deprecated_by` | list | No | IDs of documents replacing this one. |

### Allowed Values

**Role:**
- `norm`: Architectural rules and invariants.
- `reality`: Observed runtime state.
- `action`: Operational procedures.
- `runbooks`: Specific execution guides.

**Status:**
- `active`: Currently in use.
- `deprecated`: Replaced or obsolete, kept for reference.
- `experimental`: Testing or unproven concepts.
- `archived`: No longer relevant, retained for history.

**Canonicality:**
- `canonical`: Authoritative truth.
- `derived`: Generated or derived from another truth.
- `explanatory`: General guide or overview.

**Doc Type:**
- `identity`, `architecture`, `decision`, `runbook`, `guide`, `reference`, `policy`, `status`, `generated`, `archive`, `experimental`.

## 2. Repo Index (`manifest/repo-index.yaml`)

The central manifest maps the filesystem to the documentation zones.

**Structure:**
- `zones`: Dictionary of zones (`norm`, `reality`, etc.).
  - `path`: Base directory for the zone.
  - `canonical_docs`: List of filenames in that directory.
- `checks`: List of scripts that enforce repository consistency.

## 3. Review Policy (`manifest/review-policy.yaml`)

Configuration for the review freshness governance.

- `default_review_cycle_days`: Integer (default: 90).
- `mode`: `warn` or `fail`.
