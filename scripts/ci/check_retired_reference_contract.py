#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.lib.docmeta import load_repo_index, parse_frontmatter

ACTIVE_REPOSITORY_DOCUMENTS = {
    "architecture/docmeta.schema.md",
    "architecture/glossary.md",
    "runbooks/adding-docs.md",
}
HISTORICAL_ZONES = {"norm", "reality", "action", "runbooks"}
BANNER = "Historische Referenz — nicht ausführen."
FORBIDDEN_STANDARD_CHECK = "ops/checks/preflight.sh"
STATIC_CHECK = "scripts/ci/check_retired_reference_contract.py"


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    checked = 0

    manifest = load_repo_index(str(ROOT / "manifest/repo-index.yaml"))
    historical_documents: list[str] = []
    for zone_name, zone in manifest.get("zones", {}).items():
        if zone_name not in HISTORICAL_ZONES:
            continue
        base = Path(zone.get("path", ""))
        for document in zone.get("canonical_docs", []):
            path = (base / document).as_posix()
            if path not in ACTIVE_REPOSITORY_DOCUMENTS:
                historical_documents.append(path)

    for path in sorted(historical_documents):
        full_path = ROOT / path
        frontmatter = parse_frontmatter(str(full_path))
        if frontmatter is None:
            errors.append(f"{path}: missing frontmatter")
            continue
        checked += 1
        if frontmatter.get("status") not in {"deprecated", "archived"}:
            errors.append(f"{path}: status must be deprecated or archived")
        if frontmatter.get("canonicality") != "explanatory":
            errors.append(f"{path}: canonicality must be explanatory")
        verifies = frontmatter.get("verifies_with") or []
        if FORBIDDEN_STANDARD_CHECK in verifies:
            errors.append(f"{path}: host-reading preflight remains a verifier")
        if BANNER not in full_path.read_text(encoding="utf-8"):
            errors.append(f"{path}: historical non-execution banner missing")

    checks = manifest.get("checks", [])
    if FORBIDDEN_STANDARD_CHECK in checks:
        errors.append("manifest/repo-index.yaml: preflight remains a standard check")
    if STATIC_CHECK not in checks:
        errors.append("manifest/repo-index.yaml: retirement contract check missing")

    for path, section in (
        ("repo.meta.yaml", "required_checks"),
        ("agent-policy.yaml", "required_checks_before_patch"),
    ):
        text = _read(path)
        if f"  - bash {FORBIDDEN_STANDARD_CHECK}" in text or f"  - {FORBIDDEN_STANDARD_CHECK}" in text:
            errors.append(f"{path}: preflight remains in {section}")
        if STATIC_CHECK not in text:
            errors.append(f"{path}: retirement contract check missing")

    agents = _read("AGENTS.md")
    required_section = agents.split("## Erforderliche Checks", 1)[-1].split("## Häufige Fallen", 1)[0]
    if FORBIDDEN_STANDARD_CHECK in required_section:
        errors.append("AGENTS.md: preflight remains a required check")
    if STATIC_CHECK not in required_section:
        errors.append("AGENTS.md: retirement contract check missing")

    repo_meta = _read("repo.meta.yaml")
    if "status: retired-reference" not in repo_meta:
        errors.append("repo.meta.yaml: retired-reference status missing")
    canonical_section = repo_meta.split("canonical_sources:", 1)[-1].split("historical_reference_sources:", 1)[0]
    for forbidden_source in ("architecture/", "runtime/", "operations/", "runbooks/", "ops/checks/preflight.sh"):
        if forbidden_source in canonical_section:
            errors.append(f"repo.meta.yaml: historical source remains canonical: {forbidden_source}")
    if "historical_reference_sources:" not in repo_meta:
        errors.append("repo.meta.yaml: historical_reference_sources missing")

    makefile = _read("Makefile")
    preflight_section = makefile.split("preflight:", 1)[-1].split("\nsnapshot:", 1)[0]
    snapshot_section = makefile.split("snapshot:", 1)[-1].split("\nredact:", 1)[0]
    secrets_section = makefile.split("secrets:", 1)[-1].split("\nvalidate-retired-reference:", 1)[0]
    for target, section in (("preflight", preflight_section), ("snapshot", snapshot_section)):
        if "ALLOW_HISTORICAL_HOST_READ" not in section:
            errors.append(f"Makefile: {target} lacks explicit historical host-read guard")
    if "sudo" in secrets_section or "Blocked: Heimserver is retired" not in secrets_section:
        errors.append("Makefile: secrets target is not fail-closed for retired state")

    result = {
        "schemaVersion": 1,
        "kind": "retired_reference_contract",
        "checkedDocuments": checked,
        "errors": errors,
        "status": "valid" if not errors else "invalid",
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
