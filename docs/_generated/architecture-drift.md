# Architecture Drift Report

Generated automatically by `scripts/docmeta/generate-architecture-drift.py`. Do not edit.

## Structural Drift Summary
**Severity:** `warn`

The following top-level paths exist but are not tracked as canonical zones or discovery roots:
- `edge/`
- `infra/`
- `notes/`
- `security/`

## Implicit Dependencies (Infrastructure Coupling)
**Severity:** `warn`

The following scripts are actively executed by `Makefile` or reside in `scripts/ci/`, but are NOT formally registered in `audit/impl-registry.yaml`:
- `ops/checks/redact_snapshot.sh`
- `ops/checks/snapshot.sh`
- `ops/init-secrets-path.sh`
- `ops/install-hooks.sh`
- `scripts/ci/check-repo-index-consistency.sh`
- `scripts/ci/check-runbook-invariants.sh`

_Recommendation: Register these scripts to ensure they are formally tracked and documented._
