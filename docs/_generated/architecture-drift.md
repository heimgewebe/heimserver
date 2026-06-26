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

The following scripts were discovered via `Makefile` references or by scanning the `scripts/ci/` directory but are not registered in `audit/impl-registry.yaml`:
- `ops/checks/redact_snapshot.sh`
- `ops/checks/snapshot.sh`
- `ops/init-secrets-path.sh`
- `ops/install-hooks.sh`
- `scripts/ci/check-repo-index-consistency.sh`
- `scripts/ci/check-runbook-invariants.sh`
- `scripts/docmeta/generate-agent-readiness.py`
- `scripts/docmeta/generate-architecture-drift.py`
- `scripts/docmeta/generate-doc-coverage.py`
- `scripts/docmeta/generate-knowledge-gaps.py`
- `scripts/generate-relations.py`
- `scripts/generate-system-map.py`
- `scripts/tests/test_caddy_template.py`
- `scripts/tests/test_edge_compose_contract.sh`
- `scripts/tests/test_edge_sync_runbook.sh`
- `scripts/tests/test_preflight_mock.sh`

_Recommendation: Register these scripts to ensure they are formally tracked and documented._
