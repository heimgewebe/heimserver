---
id: docmeta.schema
role: norm
status: canonical
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
| `role` | enum | Yes | The zone role of the document. |
| `status` | enum | Yes | The lifecycle status. |
| `last_reviewed` | date | Yes | Date of last significant review (YYYY-MM-DD). |
| `depends_on` | list | No | List of files (paths or IDs) this doc depends on. |
| `verifies_with` | list | No | List of scripts that verify this document's truth. |

### Allowed Values

**Role:**
- `norm`: Architectural rules and invariants.
- `reality`: Observed runtime state.
- `action`: Operational procedures.
- `runbooks`: Specific execution guides.

**Status:**
- `canonical`: Active, authoritative truth.
- `draft`: Work in progress, not yet binding.
- `deprecated`: Replaced or obsolete, kept for reference.

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
